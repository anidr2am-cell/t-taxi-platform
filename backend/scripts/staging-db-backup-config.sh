#!/usr/bin/env bash
# Load non-secret staging backup automation config.
# Real secrets belong in rclone config on the server, not in this file.
set -eu

TRIDE_ROOT="/opt/t-ride"
BACKUP_ENV_FILE="${TRIDE_ROOT}/.env.backup"

export TRIDE_BACKUP_REMOTE_ENABLED="${TRIDE_BACKUP_REMOTE_ENABLED:-0}"
export TRIDE_BACKUP_AUTO_PRUNE="${TRIDE_BACKUP_AUTO_PRUNE:-0}"
export TRIDE_BACKUP_REMOTE_NAME="${TRIDE_BACKUP_REMOTE_NAME:-}"
export TRIDE_BACKUP_REMOTE_PATH="${TRIDE_BACKUP_REMOTE_PATH:-}"
export TRIDE_BACKUP_ALERT_ENABLED="${TRIDE_BACKUP_ALERT_ENABLED:-0}"
export TRIDE_BACKUP_ALERT_SCRIPT="${TRIDE_BACKUP_ALERT_SCRIPT:-}"

if [[ -f "${BACKUP_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${BACKUP_ENV_FILE}"
fi

assert_backup_config_safe() {
  if [[ "${TRIDE_BACKUP_REMOTE_ENABLED}" == "1" || "${TRIDE_BACKUP_REMOTE_ENABLED}" == "true" ]]; then
    if [[ -z "${TRIDE_BACKUP_REMOTE_NAME}" || -z "${TRIDE_BACKUP_REMOTE_PATH}" ]]; then
      echo "Remote backup enabled but TRIDE_BACKUP_REMOTE_NAME or TRIDE_BACKUP_REMOTE_PATH is empty" >&2
      exit 1
    fi
  fi
}
