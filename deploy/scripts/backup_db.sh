#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/t-ride/deploy/docker/.env"
BACKUP_DIR="/opt/t-ride/backups"
CONTAINER_NAME="tride-db"
DATE="$(date +%Y%m%d_%H%M%S)"
FILENAME="tride_backup_${DATE}.sql.gz"
FILEPATH="${BACKUP_DIR}/${FILENAME}"
RETENTION_DAYS=30
GDRIVE_REMOTE="gdrive:trider-db-backups"
RCLONE_LOG="${BACKUP_DIR}/rclone.log"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

: "${DB_USER:?DB_USER is required in ${ENV_FILE}}"
: "${DB_PASSWORD:?DB_PASSWORD is required in ${ENV_FILE}}"
: "${DB_NAME:?DB_NAME is required in ${ENV_FILE}}"

mkdir -p "${BACKUP_DIR}"
chmod 750 "${BACKUP_DIR}"

if ! docker inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "ERROR: Container not running: ${CONTAINER_NAME}" >&2
  exit 1
fi

container_db="$(docker exec "${CONTAINER_NAME}" printenv MYSQL_DATABASE || true)"
container_user="$(docker exec "${CONTAINER_NAME}" printenv MYSQL_USER || true)"
if [[ "${container_db}" != "${DB_NAME}" || "${container_user}" != "${DB_USER}" ]]; then
  echo "ERROR: .env DB settings do not match ${CONTAINER_NAME} container env" >&2
  echo "  .env DB_NAME=${DB_NAME} DB_USER=${DB_USER}" >&2
  echo "  container MYSQL_DATABASE=${container_db} MYSQL_USER=${container_user}" >&2
  exit 1
fi

echo "Starting backup for ${DB_NAME} at ${DATE}..."

if ! docker exec "${CONTAINER_NAME}" sh -lc \
  'mariadb-dump --single-transaction --routines --triggers --default-character-set=utf8mb4 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  | gzip > "${FILEPATH}"; then
  echo "ERROR: mariadb-dump failed" >&2
  rm -f "${FILEPATH}"
  exit 1
fi

if [[ ! -s "${FILEPATH}" ]]; then
  echo "ERROR: Backup file is empty: ${FILEPATH}" >&2
  exit 1
fi

if ! gzip -t "${FILEPATH}"; then
  echo "ERROR: gzip integrity check failed: ${FILEPATH}" >&2
  exit 1
fi

BACKUP_SIZE_BYTES="$(wc -c < "${FILEPATH}" | tr -d ' ')"
echo "Local backup created: ${FILEPATH} (${BACKUP_SIZE_BYTES} bytes)"

if ! command -v rclone >/dev/null 2>&1; then
  echo "ERROR: rclone is not installed" >&2
  exit 1
fi

if ! rclone copy "${FILEPATH}" "${GDRIVE_REMOTE}/" --log-file="${RCLONE_LOG}" --log-level INFO; then
  echo "ERROR: rclone upload failed" >&2
  exit 1
fi

find "${BACKUP_DIR}" -name "tride_backup_*.sql.gz" -mtime +"${RETENTION_DAYS}" -delete

if ! rclone delete "${GDRIVE_REMOTE}/" --min-age "${RETENTION_DAYS}d" --log-file="${RCLONE_LOG}" --log-level INFO; then
  echo "ERROR: rclone remote retention cleanup failed" >&2
  exit 1
fi

echo "Backup completed: ${FILENAME}"
