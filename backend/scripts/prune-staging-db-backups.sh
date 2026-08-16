#!/usr/bin/env bash
# T-Ride staging backup retention helper (dry-run by default).
# Does NOT install cron/systemd. Does NOT delete unless --apply is passed explicitly.
#
# Recommended policy (manual approval required before enabling):
# - keep 14 daily backups
# - keep 8 weekly backups (Sunday)
# - keep 6 monthly backups (first day of month)
#
# Usage:
#   bash /opt/t-ride/backend/scripts/prune-staging-db-backups.sh
#   bash /opt/t-ride/backend/scripts/prune-staging-db-backups.sh --apply
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=staging-db-backup-guards.sh
source "${SCRIPT_DIR}/staging-db-backup-guards.sh"

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
elif [[ -n "${1:-}" ]]; then
  echo "Unknown option: $1" >&2
  echo "Usage: $0 [--apply]" >&2
  exit 1
fi

assert_tride_scope

if [[ ! -d "${BACKUP_ROOT}" ]]; then
  echo "Backup directory not found: ${BACKUP_ROOT}" >&2
  exit 0
fi

mapfile -t BACKUP_FILES < <(find "${BACKUP_ROOT}" -maxdepth 1 -type f -name 'tride_staging-*.sql.gz' | sort)
TOTAL="${#BACKUP_FILES[@]}"
echo "RETENTION_POLICY_RECOMMENDED=daily:14,weekly:8,monthly:6"
echo "BACKUP_FILES_PRESENT=${TOTAL}"
echo "RETENTION_MODE=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry_run)"

if [[ "${TOTAL}" -eq 0 ]]; then
  echo "Nothing to prune."
  exit 0
fi

# Conservative placeholder: report candidates older than 14 days only.
CUTOFF_EPOCH="$(date -d '14 days ago' +%s)"
for file in "${BACKUP_FILES[@]}"; do
  file_epoch="$(date -r "${file}" +%s)"
  if [[ "${file_epoch}" -lt "${CUTOFF_EPOCH}" ]]; then
    if [[ "${APPLY}" -eq 1 ]]; then
      rm -f "${file}" "${file%.sql.gz}.manifest" 2>/dev/null || true
      echo "DELETED=${file}"
    else
      echo "CANDIDATE=${file}"
    fi
  fi
done

if [[ "${APPLY}" -eq 0 ]]; then
  echo "No files deleted (dry-run)."
fi
