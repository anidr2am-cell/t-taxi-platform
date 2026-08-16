#!/usr/bin/env bash
# T-Ride staging backup retention helper (dry-run by default).
# Uses deterministic daily/weekly/monthly buckets: 14 / 8 / 6.
# Does NOT install cron/systemd. Does NOT delete unless --apply is passed.
#
# Usage:
#   bash /opt/t-ride/backend/scripts/prune-staging-db-backups.sh
#   bash /opt/t-ride/backend/scripts/prune-staging-db-backups.sh --apply
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=staging-db-backup-guards.sh
source "${SCRIPT_DIR}/staging-db-backup-guards.sh"
# shellcheck source=staging-db-backup-retention-lib.sh
source "${SCRIPT_DIR}/staging-db-backup-retention-lib.sh"

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
elif [[ -n "${1:-}" ]]; then
  echo "Unknown option: $1" >&2
  echo "Usage: $0 [--apply]" >&2
  exit 1
fi

assert_tride_scope

backup_retention_emit_plan "${APPLY}"
