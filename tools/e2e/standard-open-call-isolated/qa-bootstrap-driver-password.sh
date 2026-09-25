#!/bin/bash
# Ephemeral QA driver password (mode 600 file). Source before fixture seed / driver login.
set -eu

if [ -n "${QA_DRIVER_PASSWORD:-}" ] || [ -n "${QA_DRIVER_PASSWORD_FILE:-}" ]; then
  exit 0
fi

QA_DRIVER_PASSWORD_FILE="$(mktemp 2>/dev/null || mktemp -t qa-driver-pw.XXXXXX)"
chmod 600 "$QA_DRIVER_PASSWORD_FILE"
if command -v openssl >/dev/null 2>&1; then
  openssl rand -base64 24 | tr -d '\n' >"$QA_DRIVER_PASSWORD_FILE"
else
  head -c 32 /dev/urandom | base64 | tr -d '\n' >"$QA_DRIVER_PASSWORD_FILE"
fi
export QA_DRIVER_PASSWORD_FILE
export QA_DRIVER_PASSWORD_EPHEMERAL=1
