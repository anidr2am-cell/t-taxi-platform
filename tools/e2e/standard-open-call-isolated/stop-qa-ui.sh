#!/bin/bash
# Stop isolated UI QA API/DB only (never touches prod tride-backend / KTaxi).
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [ -f "$ROOT/.qa-ephemeral-password-file.path" ]; then
  ep="$(tr -d '\r\n' <"$ROOT/.qa-ephemeral-password-file.path")"
  rm -f "$ep" "$ROOT/.qa-ephemeral-password-file.path" 2>/dev/null || true
fi
docker rm -f tride-qa-admin-api tride-qa-oc-true-api 2>/dev/null || true
docker stop tride-qa-admin-db 2>/dev/null || true
echo "QA_UI_STOPPED containers=tride-qa-admin-api,tride-qa-oc-true-api db=tride-qa-admin-db"
