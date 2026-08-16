#!/usr/bin/env bash
# Daily staging DB backup cycle: backup, verify, optional remote copy, gated prune.
# Does NOT install cron/systemd. Does NOT delete backups unless all gates pass.
#
# Usage:
#   bash /opt/t-ride/backend/scripts/run-staging-db-backup-cycle.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=staging-db-backup-guards.sh
source "${SCRIPT_DIR}/staging-db-backup-guards.sh"
# shellcheck source=staging-db-backup-config.sh
source "${SCRIPT_DIR}/staging-db-backup-config.sh"

BACKUP_RUNNER="${SCRIPT_DIR}/run-staging-db-backup.sh"
REMOTE_RUNNER="${SCRIPT_DIR}/staging-db-backup-remote.sh"
PRUNE_RUNNER="${SCRIPT_DIR}/prune-staging-db-backups.sh"
ALERT_RUNNER="${SCRIPT_DIR}/staging-db-backup-alert.sh"
LOCK_FILE="${TRIDE_ROOT}/logs/backups/backup-cycle.lock"
LOG_DIR="${TRIDE_ROOT}/logs/backups"
CYCLE_TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/backup-cycle-${CYCLE_TS}.log"

BACKUP_RESULT="FAIL"
REMOTE_COPY_RESULT="SKIPPED_DISABLED"
REMOTE_VERIFY_RESULT="SKIPPED_DISABLED"
LOCAL_PRUNE_RUN="NO"
BACKUP_FILE=""
MANIFEST_FILE=""
BACKUP_SHA256=""
BACKUP_SIZE_BYTES=""

mkdir -p "${LOG_DIR}"
chmod 750 "${LOG_DIR}"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "BACKUP_CYCLE=LOCKED"
  echo "Another backup cycle is already running" >&2
  exit 1
fi

log_line() {
  printf '%s\n' "$1" | tee -a "${LOG_FILE}"
}

invoke_alert() {
  local reason="$1"
  if [[ "${TRIDE_BACKUP_ALERT_ENABLED}" == "1" || "${TRIDE_BACKUP_ALERT_ENABLED}" == "true" ]]; then
    if [[ -x "${TRIDE_BACKUP_ALERT_SCRIPT}" ]]; then
      "${TRIDE_BACKUP_ALERT_SCRIPT}" "${reason}" "${LOG_FILE}" >> "${LOG_FILE}" 2>&1 || true
    elif [[ -f "${ALERT_RUNNER}" ]]; then
      bash "${ALERT_RUNNER}" "${reason}" "${LOG_FILE}" >> "${LOG_FILE}" 2>&1 || true
    fi
  fi
}

read_kv_or_default() {
  local key="$1"
  local output="$2"
  local default_value="${3:-FAIL}"
  local value
  value="$(grep -E "^${key}=" <<<"${output}" | tail -n 1 | cut -d= -f2- || true)"
  if [[ -z "${value}" ]]; then
    printf '%s' "${default_value}"
  else
    printf '%s' "${value}"
  fi
}

finish_cycle() {
  local exit_code="$1"
  log_line "CYCLE_TIMESTAMP=${CYCLE_TS}"
  log_line "BACKUP_RESULT=${BACKUP_RESULT}"
  log_line "REMOTE_COPY_RESULT=${REMOTE_COPY_RESULT}"
  log_line "REMOTE_VERIFY_RESULT=${REMOTE_VERIFY_RESULT}"
  log_line "LOCAL_PRUNE_RUN=${LOCAL_PRUNE_RUN}"
  log_line "BACKUP_FILE=${BACKUP_FILE}"
  log_line "BACKUP_SHA256=${BACKUP_SHA256}"
  log_line "BACKUP_SIZE_BYTES=${BACKUP_SIZE_BYTES}"
  log_line "LOG_FILE=${LOG_FILE}"
  if [[ "${exit_code}" -ne 0 ]]; then
    invoke_alert "backup_cycle_failed"
  fi
  exit "${exit_code}"
}

assert_tride_scope
assert_backup_config_safe

log_line "BACKUP_CYCLE=START"

BACKUP_RUNNER_EXIT=0
BACKUP_OUTPUT="$(bash "${BACKUP_RUNNER}" 2>&1 | tee -a "${LOG_FILE}")" || BACKUP_RUNNER_EXIT=$?
if [[ "${BACKUP_RUNNER_EXIT}" -ne 0 ]]; then
  log_line "Backup runner exited ${BACKUP_RUNNER_EXIT}" >&2
fi

BACKUP_FILE="$(read_kv_or_default BACKUP_FILE "${BACKUP_OUTPUT}" "")"
MANIFEST_FILE="$(read_kv_or_default MANIFEST_FILE "${BACKUP_OUTPUT}" "")"
BACKUP_RESULT="$(read_kv_or_default BACKUP_RESULT "${BACKUP_OUTPUT}" FAIL)"
BACKUP_SHA256="$(read_kv_or_default BACKUP_SHA256 "${BACKUP_OUTPUT}" "")"
BACKUP_SIZE_BYTES="$(read_kv_or_default BACKUP_SIZE_BYTES "${BACKUP_OUTPUT}" "")"

if [[ "${BACKUP_RUNNER_EXIT}" -ne 0 && "${BACKUP_RESULT}" == "PASS" ]]; then
  BACKUP_RESULT="FAIL"
fi
if [[ -z "${BACKUP_OUTPUT}" ]]; then
  BACKUP_RESULT="FAIL"
  log_line "Backup runner produced no output" >&2
fi

if [[ "${BACKUP_RESULT}" != "PASS" ]]; then
  log_line "BACKUP_CYCLE=FAIL"
  finish_cycle 1
fi
if [[ -z "${BACKUP_FILE}" || ! -f "${BACKUP_FILE}" ]]; then
  BACKUP_RESULT="FAIL"
  log_line "Backup file missing after successful runner output" >&2
  finish_cycle 1
fi
if [[ -z "${MANIFEST_FILE}" || ! -f "${MANIFEST_FILE}" ]]; then
  BACKUP_RESULT="FAIL"
  log_line "Manifest file missing after successful runner output" >&2
  finish_cycle 1
fi
if ! gzip -t "${BACKUP_FILE}"; then
  BACKUP_RESULT="FAIL"
  log_line "GZIP integrity failed during cycle verification" >&2
  finish_cycle 1
fi
ACTUAL_SHA256="$(sha256sum "${BACKUP_FILE}" | awk '{print $1}')"
MANIFEST_SHA256="$(grep -E '^BACKUP_SHA256=' "${MANIFEST_FILE}" | tail -n 1 | cut -d= -f2- || true)"
if [[ -n "${MANIFEST_SHA256}" && "${MANIFEST_SHA256}" != "${ACTUAL_SHA256}" ]]; then
  BACKUP_RESULT="FAIL"
  log_line "Manifest SHA256 mismatch during cycle verification" >&2
  finish_cycle 1
fi

REMOTE_RUNNER_EXIT=0
REMOTE_OUTPUT="$(bash "${REMOTE_RUNNER}" "${BACKUP_FILE}" "${MANIFEST_FILE}" 2>&1 | tee -a "${LOG_FILE}")" || REMOTE_RUNNER_EXIT=$?
if [[ "${REMOTE_RUNNER_EXIT}" -ne 0 ]]; then
  log_line "Remote copy runner exited ${REMOTE_RUNNER_EXIT}" >&2
fi

REMOTE_COPY_RESULT="$(read_kv_or_default REMOTE_COPY_RESULT "${REMOTE_OUTPUT}" FAIL)"
REMOTE_VERIFY_RESULT="$(read_kv_or_default REMOTE_VERIFY_RESULT "${REMOTE_OUTPUT}" FAIL)"

if [[ -z "${REMOTE_OUTPUT}" && "${REMOTE_RUNNER_EXIT}" -ne 0 ]]; then
  REMOTE_COPY_RESULT="FAIL"
  REMOTE_VERIFY_RESULT="FAIL"
  log_line "Remote copy runner produced no output" >&2
fi

if [[ "${REMOTE_COPY_RESULT}" == "FAIL" || "${REMOTE_VERIFY_RESULT}" == "FAIL" ]]; then
  log_line "BACKUP_CYCLE=FAIL"
  finish_cycle 1
fi

if [[ "${TRIDE_BACKUP_AUTO_PRUNE}" == "1" || "${TRIDE_BACKUP_AUTO_PRUNE}" == "true" ]]; then
  if [[ "${REMOTE_COPY_RESULT}" == "PASS" && "${REMOTE_VERIFY_RESULT}" == "PASS" ]]; then
    if bash "${PRUNE_RUNNER}" --apply >> "${LOG_FILE}" 2>&1; then
      LOCAL_PRUNE_RUN="YES"
    else
      LOCAL_PRUNE_RUN="FAIL"
      log_line "BACKUP_CYCLE=FAIL"
      finish_cycle 1
    fi
  else
    LOCAL_PRUNE_RUN="NO"
  fi
else
  LOCAL_PRUNE_RUN="NO"
fi

log_line "BACKUP_CYCLE=PASS"
finish_cycle 0
