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

RESTORE_RUNNER="${SCRIPT_DIR}/run-staging-db-restore-rehearsal.sh"
RETENTION_PLANNER="${SCRIPT_DIR}/staging-db-backup-retention-plan.js"
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

assert_tride_scope

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for monthly rehearsal selection" >&2
  exit 1
fi

SELECT_JSON="$(node "${RETENTION_PLANNER}" --select-latest 2>/dev/null || true)"
MONTHLY_REHEARSAL_BACKUP="$(node -e "const j=JSON.parse(process.argv[1]); console.log(j.latest?.backupPath || '')" "${SELECT_JSON}")"

if [[ -z "${MONTHLY_REHEARSAL_BACKUP}" || ! -f "${MONTHLY_REHEARSAL_BACKUP}" ]]; then
  log_line "MONTHLY_REHEARSAL_RESULT=FAIL"
  log_line "No complete backup pair found" >&2
  exit 1
fi

log_line "MONTHLY_REHEARSAL_BACKUP=${MONTHLY_REHEARSAL_BACKUP}"

if ! gzip -t "${MONTHLY_REHEARSAL_BACKUP}"; then
  log_line "MONTHLY_REHEARSAL_RESULT=FAIL"
  log_line "Selected backup failed gzip integrity" >&2
  exit 1
fi

RESTORE_OUTPUT="$("${RESTORE_RUNNER}" "${MONTHLY_REHEARSAL_BACKUP}" 2>&1 | tee -a "${LOG_FILE}")" || true
RESTORE_REHEARSAL="$(grep -E '^RESTORE_REHEARSAL=' <<<"${RESTORE_OUTPUT}" | tail -n 1 | cut -d= -f2- || echo FAIL)"
if [[ "${RESTORE_REHEARSAL}" != "PASS" ]]; then
  log_line "MONTHLY_REHEARSAL_RESULT=FAIL"
  exit 1
fi

if curl -fsS http://172.18.0.1:3100/api/v1/health >> "${LOG_FILE}" 2>&1; then
  INTERNAL_HEALTH="PASS"
fi
if curl -fsS https://trider.taxi/api/v1/health >> "${LOG_FILE}" 2>&1; then
  PUBLIC_HEALTH="PASS"
fi

log_line "RESTORE_REHEARSAL=${RESTORE_REHEARSAL}"
log_line "INTERNAL_HEALTH=${INTERNAL_HEALTH}"
log_line "PUBLIC_HEALTH=${PUBLIC_HEALTH}"

if [[ "${INTERNAL_HEALTH}" == "PASS" && "${PUBLIC_HEALTH}" == "PASS" ]]; then
  MONTHLY_REHEARSAL_RESULT="PASS"
else
  MONTHLY_REHEARSAL_RESULT="FAIL"
fi

log_line "MONTHLY_REHEARSAL_RESULT=${MONTHLY_REHEARSAL_RESULT}"
log_line "LOG_FILE=${LOG_FILE}"

if [[ "${MONTHLY_REHEARSAL_RESULT}" != "PASS" ]]; then
  exit 1
fi
