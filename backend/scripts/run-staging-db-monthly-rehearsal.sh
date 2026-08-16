#!/usr/bin/env bash
# Monthly isolated restore rehearsal against latest complete local backup pair.
# Does NOT restore into tride-db or tride_staging.
#
# Usage:
#   bash /opt/t-ride/backend/scripts/run-staging-db-monthly-rehearsal.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=staging-db-backup-guards.sh
source "${SCRIPT_DIR}/staging-db-backup-guards.sh"
# shellcheck source=staging-db-backup-config.sh
source "${SCRIPT_DIR}/staging-db-backup-config.sh"
# shellcheck source=staging-db-backup-retention-lib.sh
source "${SCRIPT_DIR}/staging-db-backup-retention-lib.sh"

RESTORE_RUNNER="${SCRIPT_DIR}/run-staging-db-restore-rehearsal.sh"
LOG_DIR="${TRIDE_ROOT}/logs/backups"
REHEARSAL_TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/monthly-rehearsal-${REHEARSAL_TS}.log"

MONTHLY_REHEARSAL_BACKUP=""
RESTORE_REHEARSAL="FAIL"
INTERNAL_HEALTH="FAIL"
PUBLIC_HEALTH="FAIL"
MONTHLY_REHEARSAL_RESULT="FAIL"

mkdir -p "${LOG_DIR}"
chmod 750 "${LOG_DIR}"

log_line() {
  printf '%s\n' "$1" | tee -a "${LOG_FILE}"
}

log_monthly_diagnostics() {
  log_line "MONTHLY_REHEARSAL_BACKUP=${MONTHLY_REHEARSAL_BACKUP}"
  log_line "RESTORE_REHEARSAL=${RESTORE_REHEARSAL}"
  log_line "INTERNAL_HEALTH=${INTERNAL_HEALTH}"
  log_line "PUBLIC_HEALTH=${PUBLIC_HEALTH}"
  log_line "MONTHLY_REHEARSAL_RESULT=${MONTHLY_REHEARSAL_RESULT}"
}

finish_monthly_fail() {
  local message="${1:-}"
  if [[ -n "${message}" ]]; then
    log_line "${message}" >&2
  fi
  log_monthly_diagnostics
  log_line "LOG_FILE=${LOG_FILE}"
  exit 1
}

assert_tride_scope

MONTHLY_REHEARSAL_BACKUP="$(backup_retention_select_latest_backup_path || true)"
if [[ -z "${MONTHLY_REHEARSAL_BACKUP}" || ! -f "${MONTHLY_REHEARSAL_BACKUP}" ]]; then
  finish_monthly_fail "No complete backup pair found"
fi

log_line "MONTHLY_REHEARSAL_BACKUP=${MONTHLY_REHEARSAL_BACKUP}"

if ! gzip -t "${MONTHLY_REHEARSAL_BACKUP}"; then
  RESTORE_REHEARSAL="FAIL"
  finish_monthly_fail "Selected backup failed gzip integrity"
fi

RESTORE_RUNNER_EXIT=0
RESTORE_OUTPUT="$(bash "${RESTORE_RUNNER}" "${MONTHLY_REHEARSAL_BACKUP}" 2>&1 | tee -a "${LOG_FILE}")" || RESTORE_RUNNER_EXIT=$?
if [[ "${RESTORE_RUNNER_EXIT}" -ne 0 ]]; then
  log_line "Restore rehearsal runner exited ${RESTORE_RUNNER_EXIT}" >&2
fi
RESTORE_REHEARSAL="$(grep -E '^RESTORE_REHEARSAL=' <<<"${RESTORE_OUTPUT}" | tail -n 1 | cut -d= -f2- || true)"
if [[ -z "${RESTORE_REHEARSAL}" ]]; then
  RESTORE_REHEARSAL="FAIL"
fi
if [[ "${RESTORE_RUNNER_EXIT}" -ne 0 && "${RESTORE_REHEARSAL}" == "PASS" ]]; then
  RESTORE_REHEARSAL="FAIL"
fi
if [[ -z "${RESTORE_OUTPUT}" ]]; then
  RESTORE_REHEARSAL="FAIL"
  log_line "Restore rehearsal runner produced no output" >&2
fi
if [[ "${RESTORE_REHEARSAL}" != "PASS" ]]; then
  finish_monthly_fail "Restore rehearsal failed"
fi

if curl -fsS http://172.18.0.1:3100/api/v1/health >> "${LOG_FILE}" 2>&1; then
  INTERNAL_HEALTH="PASS"
fi
if curl -fsS https://trider.taxi/api/v1/health >> "${LOG_FILE}" 2>&1; then
  PUBLIC_HEALTH="PASS"
fi

if [[ "${INTERNAL_HEALTH}" == "PASS" && "${PUBLIC_HEALTH}" == "PASS" ]]; then
  MONTHLY_REHEARSAL_RESULT="PASS"
else
  MONTHLY_REHEARSAL_RESULT="FAIL"
fi

log_monthly_diagnostics
log_line "LOG_FILE=${LOG_FILE}"

if [[ "${MONTHLY_REHEARSAL_RESULT}" != "PASS" ]]; then
  exit 1
fi
