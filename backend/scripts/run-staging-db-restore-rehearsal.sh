#!/usr/bin/env bash
# Isolated restore rehearsal for a T-Ride staging DB backup.
# Uses disposable MariaDB 10.11 container tride-restore-rehearsal with tmpfs storage.
# NEVER restores into tride-db or tride_staging.
#
# Usage:
#   bash /opt/t-ride/backend/scripts/run-staging-db-restore-rehearsal.sh \
#     /opt/t-ride/backups/tride_staging-YYYYMMDD-HHMMSS.sql.gz
#
# Health checks (run manually after live rehearsal):
#   curl -fsS http://172.18.0.1:3100/api/v1/health
#   curl -fsS https://trider.taxi/api/v1/health
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=staging-db-backup-guards.sh
source "${SCRIPT_DIR}/staging-db-backup-guards.sh"

BACKUP_FILE="${1:?backup .sql.gz path required}"
VERIFY_SQL="${SCRIPT_DIR}/staging-db-restore-rehearsal-verify.sql"
READINESS_TIMEOUT_SECONDS="${READINESS_TIMEOUT_SECONDS:-120}"
REHEARSAL_ROOT_PASSWORD=""

cleanup() {
  local rc=$?
  docker rm -f "${REHEARSAL_CONTAINER}" >/dev/null 2>&1 || true
  exit "${rc}"
}
trap cleanup EXIT

assert_tride_scope
assert_backup_path_allowed "${BACKUP_FILE}"
assert_no_prune_commands "${BASH_SOURCE[0]}"
assert_no_staging_drop "${BASH_SOURCE[0]}"

if [[ ! -f "${BACKUP_FILE}" ]]; then
  echo "Backup file not found: ${BACKUP_FILE}" >&2
  exit 1
fi

if [[ ! -f "${VERIFY_SQL}" ]]; then
  echo "Missing verification SQL: ${VERIFY_SQL}" >&2
  exit 1
fi

MANIFEST_FILE="${BACKUP_FILE%.sql.gz}.manifest"
if [[ ! -f "${MANIFEST_FILE}" ]]; then
  echo "Missing manifest file: ${MANIFEST_FILE}" >&2
  exit 1
fi

MANIFEST_SHA256="$(grep -E '^BACKUP_SHA256=' "${MANIFEST_FILE}" | tail -n 1 | cut -d= -f2- || true)"
ACTUAL_SHA256="$(sha256sum "${BACKUP_FILE}" | awk '{print $1}')"
if [[ -n "${MANIFEST_SHA256}" && "${MANIFEST_SHA256}" != "${ACTUAL_SHA256}" ]]; then
  echo "Backup SHA256 mismatch (manifest vs file)" >&2
  exit 1
fi

if ! gzip -t "${BACKUP_FILE}"; then
  echo "GZIP_TEST=FAIL"
  echo "RESTORE_REHEARSAL=FAIL"
  exit 1
fi
echo "GZIP_TEST=PASS"

docker rm -f "${REHEARSAL_CONTAINER}" >/dev/null 2>&1 || true

REHEARSAL_ROOT_PASSWORD="$(openssl rand -hex 24)"
if ! docker run -d \
  --name "${REHEARSAL_CONTAINER}" \
  --tmpfs /var/lib/mysql:rw,noexec,nosuid,size=2048m \
  -e "MYSQL_ROOT_PASSWORD=${REHEARSAL_ROOT_PASSWORD}" \
  "${MARIADB_IMAGE}" \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  >/dev/null; then
  echo "RESTORE_REHEARSAL=FAIL"
  echo "Failed to start rehearsal container" >&2
  exit 1
fi

ready=0
for _ in $(seq 1 "${READINESS_TIMEOUT_SECONDS}"); do
  if docker exec "${REHEARSAL_CONTAINER}" sh -lc \
    'mysqladmin ping -h 127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --silent' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "${ready}" -ne 1 ]]; then
  echo "RESTORE_REHEARSAL=FAIL"
  echo "MariaDB readiness timeout" >&2
  exit 1
fi

docker exec "${REHEARSAL_CONTAINER}" sh -lc \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE `'"${REHEARSAL_DB}"'` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"' \
  >/dev/null

if ! gzip -dc "${BACKUP_FILE}" \
  | sed "s/\`${SOURCE_DB}\`/\`${REHEARSAL_DB}\`/g" \
  | docker exec -i "${REHEARSAL_CONTAINER}" sh -lc \
      'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "'"${REHEARSAL_DB}"'"' \
  >/dev/null; then
  echo "RESTORE_REHEARSAL=FAIL"
  echo "SQL restore failed" >&2
  exit 1
fi

docker cp "${VERIFY_SQL}" "${REHEARSAL_CONTAINER}:/tmp/staging-db-restore-rehearsal-verify.sql"
VERIFY_TMP="$(mktemp)"
docker exec "${REHEARSAL_CONTAINER}" sh -lc \
  'mysql -N -uroot -p"$MYSQL_ROOT_PASSWORD" "'"${REHEARSAL_DB}"'" < /tmp/staging-db-restore-rehearsal-verify.sql' \
  > "${VERIFY_TMP}"

compare_manifest_key() {
  local key="$1"
  local expected actual
  expected="$(grep -E "^${key}=" "${MANIFEST_FILE}" | tail -n 1 | cut -d= -f2- || true)"
  actual="$(grep -E "^${key}=" "${VERIFY_TMP}" | tail -n 1 | cut -d= -f2- || true)"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "Manifest mismatch ${key}: expected=${expected} actual=${actual}" >&2
    return 1
  fi
  echo "${key}=${actual}"
  return 0
}

COMPARE_KEYS=(
  TABLE_COUNT
  ROW_COUNT_bookings
  ROW_COUNT_booking_driver_assignments
  ROW_COUNT_notifications
  ROW_COUNT_users
  ROW_COUNT_drivers
  ROW_COUNT_booking_contact_connections
  ROW_COUNT_booking_idempotency_keys
  ROW_COUNT_settlement_receipt_idempotency
  CONSTRAINT_uk_notifications_idempotency
  CONSTRAINT_uk_bcc_one_active_per_booking
  CONSTRAINT_uk_booking_idempotency_key
  CONSTRAINT_uk_settlement_receipt_idempotency_scope
  LATEST_BOOKING_NUMBER
  LATEST_BOOKING_CREATED_AT
)

for key in "${COMPARE_KEYS[@]}"; do
  if ! compare_manifest_key "${key}"; then
    echo "RESTORE_REHEARSAL=FAIL"
    exit 1
  fi
done

echo "RESTORE_DB=${REHEARSAL_DB}"
echo "RESTORE_CONTAINER=${REHEARSAL_CONTAINER}"
echo "RESTORE_USES_TRIDE_DB=NO"
echo "RESTORE_USES_TRIDE_MYSQL_VOLUME=NO"
echo "PUBLIC_PORT_PUBLISHED=NO"
echo "SOURCE_RESTORE_COMPARISON_METHOD=manifest_from_pre_dump_select_vs_restored_select"
echo "RESTORE_REHEARSAL=PASS"

rm -f "${VERIFY_TMP}" 2>/dev/null || true
