#!/usr/bin/env bash
# Staging-only logical backup for tride_staging via tride-db (MariaDB 10.11).
# Safe scope: /opt/t-ride, tride-db, tride_staging only.
#
# Usage (on Gabia staging host):
#   bash /opt/t-ride/backend/scripts/run-staging-db-backup.sh
#
# Does NOT run restore, prune, or touch ktaxi-*.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=staging-db-backup-guards.sh
source "${SCRIPT_DIR}/staging-db-backup-guards.sh"

ENV_FILE="/opt/t-ride/deploy/docker/.env"
MANIFEST_SQL="${SCRIPT_DIR}/staging-db-backup-manifest.sql"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

assert_tride_scope
assert_source_db_name "${DB_NAME:-}"
assert_source_container_name "${SOURCE_CONTAINER}"

if ! docker inspect "${SOURCE_CONTAINER}" >/dev/null 2>&1; then
  echo "Source container not running: ${SOURCE_CONTAINER}" >&2
  exit 1
fi

if [[ ! -f "${MANIFEST_SQL}" ]]; then
  echo "Missing manifest SQL: ${MANIFEST_SQL}" >&2
  exit 1
fi

mkdir -p "${BACKUP_ROOT}"
chmod 750 "${BACKUP_ROOT}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FINAL_FILE="${BACKUP_ROOT}/${SOURCE_DB}-${TIMESTAMP}.sql.gz"
PARTIAL_FILE="${FINAL_FILE}.partial"
MANIFEST_FILE="${BACKUP_ROOT}/${SOURCE_DB}-${TIMESTAMP}.manifest"
MANIFEST_TMP="$(mktemp)"
ENGINE_VERSION=""

cleanup_partial() {
  rm -f "${PARTIAL_FILE}" "${MANIFEST_TMP}" 2>/dev/null || true
}
trap cleanup_partial EXIT

echo "Capturing pre-dump manifest snapshot..."
docker cp "${MANIFEST_SQL}" "${SOURCE_CONTAINER}:/tmp/staging-db-backup-manifest.sql"
docker exec "${SOURCE_CONTAINER}" sh -lc \
  'mysql -N -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /tmp/staging-db-backup-manifest.sql' \
  > "${MANIFEST_TMP}"

ENGINE_VERSION="$(grep -E '^DB_ENGINE_VERSION=' "${MANIFEST_TMP}" | tail -n 1 | cut -d= -f2- || true)"
HIGHEST_MIGRATION="$(
  find /opt/t-ride/database -maxdepth 1 -type f -name '[0-9]*_*.sql' -printf '%f\n' 2>/dev/null \
    | sort \
    | tail -n 1 \
    || true
)"

{
  echo "BACKUP_TIMESTAMP=${TIMESTAMP}"
  echo "DB_NAME=${SOURCE_DB}"
  echo "DB_CONTAINER=${SOURCE_CONTAINER}"
  echo "DB_ENGINE_VERSION=${ENGINE_VERSION}"
  echo "SOURCE_HOST_SCOPE=${TRIDE_ROOT}"
  echo "BACKUP_SNAPSHOT_METHOD=pre_dump_select_plus_single_transaction_dump"
  echo "HIGHEST_REPO_MIGRATION_FILE=${HIGHEST_MIGRATION}"
  cat "${MANIFEST_TMP}"
} > "${MANIFEST_FILE}"
chmod 640 "${MANIFEST_FILE}"

echo "Starting mariadb-dump..."
if ! docker exec "${SOURCE_CONTAINER}" sh -lc \
  'mariadb-dump --single-transaction --quick --routines --triggers --events --default-character-set=utf8mb4 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  | gzip > "${PARTIAL_FILE}"; then
  echo "BACKUP_RESULT=FAIL"
  echo "Backup dump failed" >&2
  exit 1
fi

if [[ ! -s "${PARTIAL_FILE}" ]]; then
  echo "BACKUP_RESULT=FAIL"
  echo "Backup dump produced empty file" >&2
  exit 1
fi

if ! gzip -t "${PARTIAL_FILE}"; then
  echo "BACKUP_RESULT=FAIL"
  echo "GZIP integrity test failed before finalization" >&2
  exit 1
fi

mv "${PARTIAL_FILE}" "${FINAL_FILE}"
chmod 640 "${FINAL_FILE}"
trap - EXIT

if ! gzip -t "${FINAL_FILE}"; then
  echo "BACKUP_RESULT=FAIL"
  echo "GZIP integrity test failed after finalization" >&2
  exit 1
fi

BACKUP_SHA256="$(sha256sum "${FINAL_FILE}" | awk '{print $1}')"
BACKUP_SIZE_BYTES="$(wc -c < "${FINAL_FILE}" | tr -d ' ')"

{
  echo "BACKUP_FILE=${FINAL_FILE}"
  echo "BACKUP_SHA256=${BACKUP_SHA256}"
  echo "BACKUP_SIZE_BYTES=${BACKUP_SIZE_BYTES}"
} >> "${MANIFEST_FILE}"

echo "BACKUP_FILE=${FINAL_FILE}"
echo "BACKUP_SIZE_BYTES=${BACKUP_SIZE_BYTES}"
echo "BACKUP_SHA256=${BACKUP_SHA256}"
echo "GZIP_TEST=PASS"
echo "BACKUP_RESULT=PASS"
echo "MANIFEST_FILE=${MANIFEST_FILE}"
