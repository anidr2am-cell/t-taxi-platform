#!/usr/bin/env bash
# Backup inventory and retention planning for host-level T-Ride staging ops.
# Pure bash inventory and retention helpers for host-level staging ops.

RETENTION_DAILY_LIMIT=14
RETENTION_WEEKLY_LIMIT=8
RETENTION_MONTHLY_LIMIT=6

backup_retention_backup_root() {
  printf '%s\n' "${TRIDE_BACKUP_ROOT:-${BACKUP_ROOT:-/opt/t-ride/backups}}"
}

backup_retention_parse_filename() {
  local base="${1##*/}"
  if [[ ! "${base}" =~ ^tride_staging-[0-9]{8}-[0-9]{6}\.sql\.gz$ ]]; then
    return 1
  fi
  local rest="${base#tride_staging-}"
  BACKUP_RET_DATE_PART="${rest:0:8}"
  BACKUP_RET_TIME_PART="${rest:9:6}"
  BACKUP_RET_FILENAME="${base}"
  BACKUP_RET_MANIFEST_NAME="${base%.sql.gz}.manifest"
  BACKUP_RET_DAY_KEY="${BACKUP_RET_DATE_PART}"
  BACKUP_RET_MONTH_KEY="${BACKUP_RET_DATE_PART:0:6}"
  BACKUP_RET_SORT_KEY="${BACKUP_RET_DATE_PART}-${BACKUP_RET_TIME_PART}"
  return 0
}

backup_retention_iso_week_key() {
  local date_part="$1"
  local year="${date_part:0:4}"
  local month="${date_part:4:2}"
  local day="${date_part:6:2}"
  BACKUP_RET_WEEK_KEY="$(date -u -d "${year}-${month}-${day}" +%G-W%V 2>/dev/null || true)"
  if [[ -z "${BACKUP_RET_WEEK_KEY}" ]]; then
    return 1
  fi
  return 0
}

backup_retention_manifest_value() {
  local manifest_path="$1"
  local key="$2"
  grep -E "^${key}=" "${manifest_path}" 2>/dev/null | tail -n 1 | cut -d= -f2- || true
}

backup_retention_manifest_valid_for_backup() {
  local backup_name="$1"
  local manifest_path="$2"
  local backup_path="$3"

  if [[ ! -f "${manifest_path}" ]]; then
    return 1
  fi

  local sha256 size manifest_file manifest_size
  sha256="$(backup_retention_manifest_value "${manifest_path}" BACKUP_SHA256)"
  if [[ -z "${sha256}" ]]; then
    return 1
  fi

  manifest_file="$(backup_retention_manifest_value "${manifest_path}" BACKUP_FILE)"
  if [[ -n "${manifest_file}" && "${manifest_file##*/}" != "${backup_name}" ]]; then
    return 1
  fi

  if [[ ! -f "${backup_path}" ]]; then
    return 1
  fi

  size="$(stat -c '%s' "${backup_path}" 2>/dev/null || wc -c < "${backup_path}")"
  manifest_size="$(backup_retention_manifest_value "${manifest_path}" BACKUP_SIZE_BYTES)"
  if [[ -n "${manifest_size}" && "${manifest_size}" != "${size}" ]]; then
    return 1
  fi

  return 0
}

backup_retention_reset_inventory() {
  BACKUP_RET_VALID_ENTRIES=()
  BACKUP_RET_MALFORMED=()
  BACKUP_RET_ORPHAN_BACKUPS=()
  BACKUP_RET_ORPHAN_MANIFESTS=()
}

backup_retention_inventory() {
  local backup_root
  backup_root="$(backup_retention_backup_root)"
  backup_retention_reset_inventory

  if [[ ! -d "${backup_root}" ]]; then
    return 0
  fi

  local -a backup_names=()
  local -a manifest_names=()
  local name base

  shopt -s nullglob
  for path in "${backup_root}"/*; do
    name="${path##*/}"
    if [[ "${name}" == *.sql.gz ]]; then
      if backup_retention_parse_filename "${name}"; then
        backup_names+=("${name}")
      else
        BACKUP_RET_MALFORMED+=("${name}")
      fi
    elif [[ "${name}" == *.manifest ]]; then
      manifest_names+=("${name}")
    fi
  done
  shopt -u nullglob

  local -A backup_name_set=()
  for name in "${backup_names[@]}"; do
    backup_name_set["${name}"]=1
  done

  for name in "${backup_names[@]}"; do
    backup_retention_parse_filename "${name}"
    local backup_path="${backup_root}/${name}"
    local manifest_path="${backup_root}/${BACKUP_RET_MANIFEST_NAME}"
    if ! backup_retention_manifest_valid_for_backup "${name}" "${manifest_path}" "${backup_path}"; then
      BACKUP_RET_ORPHAN_BACKUPS+=("${name}")
      continue
    fi
    backup_retention_iso_week_key "${BACKUP_RET_DATE_PART}" || continue
    BACKUP_RET_VALID_ENTRIES+=("${BACKUP_RET_SORT_KEY}|${name}|${BACKUP_RET_DAY_KEY}|${BACKUP_RET_MONTH_KEY}|${BACKUP_RET_WEEK_KEY}|${backup_path}|${manifest_path}")
  done

  for name in "${manifest_names[@]}"; do
    local expected_backup="${name%.manifest}.sql.gz"
    if [[ -z "${backup_name_set[${expected_backup}]+x}" ]]; then
      BACKUP_RET_ORPHAN_MANIFESTS+=("${name}")
    fi
  done

  if ((${#BACKUP_RET_VALID_ENTRIES[@]} > 0)); then
    IFS=$'\n' BACKUP_RET_VALID_ENTRIES=($(printf '%s\n' "${BACKUP_RET_VALID_ENTRIES[@]}" | sort -r -t'|' -k1,1))
    unset IFS
  fi
}

backup_retention_entry_field() {
  local entry="$1"
  local index="$2"
  printf '%s' "${entry}" | awk -F'|' -v idx="${index}" '{print $idx}'
}

backup_retention_select_latest_backup_path() {
  backup_retention_inventory
  if ((${#BACKUP_RET_VALID_ENTRIES[@]} == 0)); then
    printf '\n'
    return 1
  fi
  backup_retention_entry_field "${BACKUP_RET_VALID_ENTRIES[0]}" 6
  return 0
}

backup_retention_classify() {
  backup_retention_inventory

  local -a keep=()
  local -a delete_candidates=()
  local -a tier_assignments=()
  local -A keep_set=()

  local entry filename day_key month_key week_key
  local month_count=0 week_count=0 day_count=0
  local -A month_seen=()
  local -A week_seen=()
  local -A day_seen=()

  if ((${#BACKUP_RET_VALID_ENTRIES[@]} > 0)); then
    filename="$(backup_retention_entry_field "${BACKUP_RET_VALID_ENTRIES[0]}" 2)"
    keep+=("${filename}")
    keep_set["${filename}"]=1
    tier_assignments+=("KEEP_NEWEST=${filename}")
  fi

  for entry in "${BACKUP_RET_VALID_ENTRIES[@]}"; do
    if ((month_count >= RETENTION_MONTHLY_LIMIT)); then
      break
    fi
    month_key="$(backup_retention_entry_field "${entry}" 4)"
    filename="$(backup_retention_entry_field "${entry}" 2)"
    if [[ -n "${month_seen[${month_key}]+x}" ]]; then
      continue
    fi
    month_seen["${month_key}"]=1
    if [[ -z "${keep_set[${filename}]+x}" ]]; then
      tier_assignments+=("KEEP_MONTHLY=${filename}")
    fi
    keep_set["${filename}"]=1
    keep+=("${filename}")
    month_count=$((month_count + 1))
  done

  for entry in "${BACKUP_RET_VALID_ENTRIES[@]}"; do
    if ((week_count >= RETENTION_WEEKLY_LIMIT)); then
      break
    fi
    week_key="$(backup_retention_entry_field "${entry}" 5)"
    filename="$(backup_retention_entry_field "${entry}" 2)"
    if [[ -n "${week_seen[${week_key}]+x}" ]]; then
      continue
    fi
    week_seen["${week_key}"]=1
    if [[ -z "${keep_set[${filename}]+x}" ]]; then
      tier_assignments+=("KEEP_WEEKLY=${filename}")
    fi
    keep_set["${filename}"]=1
    keep+=("${filename}")
    week_count=$((week_count + 1))
  done

  for entry in "${BACKUP_RET_VALID_ENTRIES[@]}"; do
    if ((day_count >= RETENTION_DAILY_LIMIT)); then
      break
    fi
    day_key="$(backup_retention_entry_field "${entry}" 3)"
    filename="$(backup_retention_entry_field "${entry}" 2)"
    if [[ -n "${day_seen[${day_key}]+x}" ]]; then
      continue
    fi
    day_seen["${day_key}"]=1
    if [[ -z "${keep_set[${filename}]+x}" ]]; then
      tier_assignments+=("KEEP_DAILY=${filename}")
    fi
    keep_set["${filename}"]=1
    keep+=("${filename}")
    day_count=$((day_count + 1))
  done

  local -a unique_keep=()
  local -A seen_keep=()
  for filename in "${keep[@]}"; do
    if [[ -z "${seen_keep[${filename}]+x}" ]]; then
      unique_keep+=("${filename}")
      seen_keep["${filename}"]=1
    fi
  done

  for entry in "${BACKUP_RET_VALID_ENTRIES[@]}"; do
    filename="$(backup_retention_entry_field "${entry}" 2)"
    if [[ -z "${keep_set[${filename}]+x}" ]]; then
      delete_candidates+=("${filename}")
    fi
  done

  BACKUP_RET_KEEP=("${unique_keep[@]}")
  BACKUP_RET_DELETE_CANDIDATES=("${delete_candidates[@]}")
  BACKUP_RET_TIER_ASSIGNMENTS=("${tier_assignments[@]}")
}

backup_retention_assert_deletable_path() {
  local target="$1"
  local backup_root resolved
  backup_root="$(backup_retention_backup_root)"
  resolved="$(readlink -f "${target}" 2>/dev/null || realpath "${target}")"
  if [[ "${resolved}" != "${backup_root}/"* ]]; then
    echo "Refusing to delete path outside ${backup_root}: ${target}" >&2
    return 1
  fi
  if [[ "${resolved}" == /opt/ktaxi/* ]]; then
    echo "Refusing to delete path under /opt/ktaxi: ${target}" >&2
    return 1
  fi
  return 0
}

backup_retention_emit_plan() {
  local apply_mode="${1:-0}"
  backup_retention_classify
  local backup_root
  backup_root="$(backup_retention_backup_root)"

  printf 'RETENTION_POLICY=daily:%s,weekly:%s,monthly:%s\n' \
    "${RETENTION_DAILY_LIMIT}" "${RETENTION_WEEKLY_LIMIT}" "${RETENTION_MONTHLY_LIMIT}"
  printf 'BACKUP_FILES_VALID=%s\n' "${#BACKUP_RET_VALID_ENTRIES[@]}"
  printf 'RETENTION_KEEP_COUNT=%s\n' "${#BACKUP_RET_KEEP[@]}"
  printf 'RETENTION_DELETE_CANDIDATES=%s\n' "${#BACKUP_RET_DELETE_CANDIDATES[@]}"
  if [[ "${apply_mode}" == "1" ]]; then
    printf 'RETENTION_MODE=apply\n'
  else
    printf 'RETENTION_MODE=dry_run\n'
  fi

  local name assignment
  for name in "${BACKUP_RET_MALFORMED[@]}"; do
    printf 'MALFORMED=%s\n' "${name}"
  done
  for name in "${BACKUP_RET_ORPHAN_BACKUPS[@]}"; do
    printf 'ORPHAN_BACKUP=%s\n' "${name}"
  done
  for name in "${BACKUP_RET_ORPHAN_MANIFESTS[@]}"; do
    printf 'ORPHAN_MANIFEST=%s\n' "${name}"
  done
  for assignment in "${BACKUP_RET_TIER_ASSIGNMENTS[@]}"; do
    printf '%s\n' "${assignment}"
  done
  for name in "${BACKUP_RET_DELETE_CANDIDATES[@]}"; do
    printf 'CANDIDATE=%s\n' "${name}"
  done

  if [[ "${apply_mode}" == "1" ]]; then
    local backup_path manifest_path
    for name in "${BACKUP_RET_DELETE_CANDIDATES[@]}"; do
      backup_path="${backup_root}/${name}"
      manifest_path="${backup_root}/${name%.sql.gz}.manifest"
      backup_retention_assert_deletable_path "${backup_path}" || return 1
      backup_retention_assert_deletable_path "${manifest_path}" || return 1
      rm -f "${backup_path}" "${manifest_path}"
      printf 'DELETED=%s\n' "${backup_path}"
    done
  else
    printf '%s\n' 'No files deleted (dry-run).'
  fi
}
