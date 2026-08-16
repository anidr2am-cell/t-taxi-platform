#!/usr/bin/env bash
# Off-server copy for staging DB backups via rclone abstraction.
# Uploads backup + manifest and verifies remote presence/size.
#
# Usage:
#   bash staging-db-backup-remote.sh <backup.sql.gz> <backup.manifest>
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=staging-db-backup-config.sh
source "${SCRIPT_DIR}/staging-db-backup-config.sh"
# shellcheck source=staging-db-backup-guards.sh
source "${SCRIPT_DIR}/staging-db-backup-guards.sh"

BACKUP_FILE="${1:?backup file required}"
MANIFEST_FILE="${2:?manifest file required}"

assert_tride_scope
assert_backup_path_allowed "${BACKUP_FILE}"

if [[ ! -f "${MANIFEST_FILE}" ]]; then
  echo "REMOTE_COPY_RESULT=FAIL"
  echo "Manifest not found: ${MANIFEST_FILE}" >&2
  exit 1
fi

if [[ "${TRIDE_BACKUP_REMOTE_ENABLED}" != "1" && "${TRIDE_BACKUP_REMOTE_ENABLED}" != "true" ]]; then
  echo "REMOTE_COPY_RESULT=SKIPPED_DISABLED"
  echo "REMOTE_VERIFY_RESULT=SKIPPED_DISABLED"
  exit 0
fi

assert_backup_config_safe

if ! command -v rclone >/dev/null 2>&1; then
  echo "REMOTE_COPY_RESULT=FAIL"
  echo "rclone not available" >&2
  exit 1
fi

BACKUP_BASE="$(basename "${BACKUP_FILE}")"
MANIFEST_BASE="$(basename "${MANIFEST_FILE}")"
DATE_PART="${BACKUP_BASE#tride_staging-}"
DATE_PART="${DATE_PART%%-*}"
YEAR="${DATE_PART:0:4}"
MONTH="${DATE_PART:4:2}"
REMOTE_DIR="${TRIDE_BACKUP_REMOTE_NAME}:${TRIDE_BACKUP_REMOTE_PATH}/staging/db/${YEAR}/${MONTH}"
REMOTE_BACKUP="${REMOTE_DIR}/${BACKUP_BASE}"
REMOTE_MANIFEST="${REMOTE_DIR}/${MANIFEST_BASE}"

LOCAL_SIZE="$(wc -c < "${BACKUP_FILE}" | tr -d ' ')"

if ! rclone copyto "${BACKUP_FILE}" "${REMOTE_BACKUP}"; then
  echo "REMOTE_COPY_RESULT=FAIL"
  exit 1
fi
if ! rclone copyto "${MANIFEST_FILE}" "${REMOTE_MANIFEST}"; then
  echo "REMOTE_COPY_RESULT=FAIL"
  exit 1
fi

REMOTE_SIZE="$(rclone lsl "${REMOTE_BACKUP}" 2>/dev/null | awk '{print $1}' | head -n 1 || true)"
if [[ -z "${REMOTE_SIZE}" ]]; then
  echo "REMOTE_COPY_RESULT=FAIL"
  echo "REMOTE_VERIFY_RESULT=FAIL"
  echo "Remote backup object missing" >&2
  exit 1
fi
if [[ "${REMOTE_SIZE}" != "${LOCAL_SIZE}" ]]; then
  echo "REMOTE_COPY_RESULT=FAIL"
  echo "REMOTE_VERIFY_RESULT=FAIL"
  echo "Remote size mismatch" >&2
  exit 1
fi
if ! rclone lsl "${REMOTE_MANIFEST}" >/dev/null 2>&1; then
  echo "REMOTE_COPY_RESULT=FAIL"
  echo "REMOTE_VERIFY_RESULT=FAIL"
  echo "Remote manifest object missing" >&2
  exit 1
fi

echo "REMOTE_BACKUP=${REMOTE_BACKUP}"
echo "REMOTE_MANIFEST=${REMOTE_MANIFEST}"
echo "REMOTE_COPY_RESULT=PASS"
echo "REMOTE_VERIFY_RESULT=PASS"
