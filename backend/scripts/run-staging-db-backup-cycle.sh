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
    elif [[ -x "${ALERT_RUNNER}" ]]; then
      "${ALERT_RUNNER}" "${reason}" "${LOG_FILE}" >> "${LOG_FILE}" 2>&1 || true
    fi
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

BACKUP_OUTPUT="$("${BACKUP_RUNNER}" 2>&1 | tee -a "${LOG_FILE}")" || true
BACKUP_FILE="$(grep -E '^BACKUP_FILE=' <<<"${BACKUP_OUTPUT}" | tail -n 1 | cut -d= -f2- || true)"
MANIFEST_FILE="$(grep -E '^MANIFEST_FILE=' <<<"${BACKUP_OUTPUT}" | tail -n 1 | cut -d= -f2- || true)"
BACKUP_RESULT="$(grep -E '^BACKUP_RESULT=' <<<"${BACKUP_OUTPUT}" | tail -n 1 | cut -d= -f2- || echo FAIL)"
BACKUP_SHA256="$(grep -E '^BACKUP_SHA256=' <<<"${BACKUP_OUTPUT}" | tail -n 1 | cut -d= -f2- || true)"
BACKUP_SIZE_BYTES="$(grep -E '^BACKUP_SIZE_BYTES=' <<<"${BACKUP_OUTPUT}" | tail -n 1 | cut -d= -f2- || true)"

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

REMOTE_OUTPUT="$("${REMOTE_RUNNER}" "${BACKUP_FILE}" "${MANIFEST_FILE}" 2>&1 | tee -a "${LOG_FILE}")" || true
REMOTE_COPY_RESULT="$(grep -E '^REMOTE_COPY_RESULT=' <<<"${REMOTE_OUTPUT}" | tail -n 1 | cut -d= -f2- || echo FAIL)"
REMOTE_VERIFY_RESULT="$(grep -E '^REMOTE_VERIFY_RESULT=' <<<"${REMOTE_OUTPUT}" | tail -n 1 | cut -d= -f2- || echo FAIL)"

if [[ "${REMOTE_COPY_RESULT}" == "FAIL" || "${REMOTE_VERIFY_RESULT}" == "FAIL" ]]; then
  log_line "BACKUP_CYCLE=FAIL"
  finish_cycle 1
fi

if [[ "${TRIDE_BACKUP_AUTO_PRUNE}" == "1" || "${TRIDE_BACKUP_AUTO_PRUNE}" == "true" ]]; then
  if [[ "${REMOTE_COPY_RESULT}" == "PASS" && "${REMOTE_VERIFY_RESULT}" == "PASS" ]]; then
    if "${PRUNE_RUNNER}" --apply >> "${LOG_FILE}" 2>&1; then
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
