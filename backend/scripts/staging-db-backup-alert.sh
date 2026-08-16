#!/usr/bin/env bash
# Provider-neutral backup failure alert hook (disabled by default).
# Enable with TRIDE_BACKUP_ALERT_ENABLED=1 and TRIDE_BACKUP_ALERT_SCRIPT pointing here.
set -eu

REASON="${1:-backup_cycle_failed}"
LOG_FILE="${2:-}"

echo "ALERT_EVENT=${REASON}"
echo "ALERT_LOG_FILE=${LOG_FILE}"
echo "ALERT_DELIVERY=LOG_ONLY"
