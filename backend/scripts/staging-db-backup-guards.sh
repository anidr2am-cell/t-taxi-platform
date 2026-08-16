#!/usr/bin/env bash
# Shared safety guards for T-Ride staging DB backup / restore rehearsal.
# Scope: /opt/t-ride and tride-* only. Never /opt/ktaxi or ktaxi-*.

TRIDE_ROOT="/opt/t-ride"
BACKUP_ROOT="${TRIDE_ROOT}/backups"
SOURCE_CONTAINER="tride-db"
SOURCE_DB="tride_staging"
REHEARSAL_CONTAINER="tride-restore-rehearsal"
REHEARSAL_DB="tride_restore_rehearsal"
MARIADB_IMAGE="mariadb:10.11"

assert_tride_scope() {
  if [[ "${TRIDE_ROOT}" == /opt/ktaxi* ]]; then
    echo "Refusing ktaxi path scope" >&2
    exit 1
  fi
}

assert_source_db_name() {
  local db_name="${1:-}"
  if [[ "${db_name}" != "${SOURCE_DB}" ]]; then
    echo "Refusing backup source DB '${db_name}'; expected ${SOURCE_DB}" >&2
    exit 1
  fi
}

assert_source_container_name() {
  local container_name="${1:-}"
  if [[ "${container_name}" != "${SOURCE_CONTAINER}" ]]; then
    echo "Refusing backup source container '${container_name}'; expected ${SOURCE_CONTAINER}" >&2
    exit 1
  fi
}

assert_backup_path_allowed() {
  local backup_file="$1"
  local resolved
  resolved="$(readlink -f "${backup_file}" 2>/dev/null || realpath "${backup_file}")"
  if [[ "${resolved}" != "${BACKUP_ROOT}/"* ]]; then
    echo "Backup path must be under ${BACKUP_ROOT}" >&2
    exit 1
  fi
  if [[ "${resolved}" == /opt/ktaxi/* ]]; then
    echo "Backup path must not be under /opt/ktaxi" >&2
    exit 1
  fi
  if [[ "${resolved}" != *.sql.gz ]]; then
    echo "Backup path must end with .sql.gz" >&2
    exit 1
  fi
}

assert_no_prune_commands() {
  local script_path="$1"
  if grep -Eq 'docker (system|volume|container) prune|docker compose down' "${script_path}"; then
    echo "Forbidden Docker cleanup command found in ${script_path}" >&2
    exit 1
  fi
}

assert_no_staging_drop() {
  local script_path="$1"
  if grep -Eiq 'DROP DATABASE[^;]*tride_staging|DROP DATABASE `tride_staging`' "${script_path}"; then
    echo "Forbidden DROP DATABASE tride_staging found in ${script_path}" >&2
    exit 1
  fi
}
