#!/bin/bash
# Ephemeral QA password file is removed when KEEP_QA_RUNNING=0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=qa-cleanup-ephemeral-driver-password.sh
source "$ROOT/qa-cleanup-ephemeral-driver-password.sh"

pw="$(mktemp 2>/dev/null || mktemp -t qa-driver-pw.XXXXXX)"
marker="$(mktemp 2>/dev/null || mktemp -t qa-ephem-marker.XXXXXX)"
printf 'x' >"$pw"
chmod 600 "$pw"
printf '%s\n' "$pw" >"$marker"

export QA_DRIVER_PASSWORD_EPHEMERAL=1
export QA_DRIVER_PASSWORD_FILE="$pw"
export QA_EPHEMERAL_MARKER="$marker"
export KEEP_QA_RUNNING=0
export SUITE_FAIL=0

qa_cleanup_ephemeral_driver_password

if [ -e "$pw" ]; then
  echo "FAIL: ephemeral password file still present after cleanup" >&2
  rm -f "$pw" "$marker" 2>/dev/null || true
  exit 1
fi
if [ -e "$marker" ]; then
  echo "FAIL: ephemeral marker still present after cleanup" >&2
  rm -f "$marker" 2>/dev/null || true
  exit 1
fi

# KEEP_QA_RUNNING=1 success must retain the file
pw2="$(mktemp 2>/dev/null || mktemp -t qa-driver-pw.XXXXXX)"
printf 'x' >"$pw2"
chmod 600 "$pw2"
export QA_DRIVER_PASSWORD_EPHEMERAL=1
export QA_DRIVER_PASSWORD_FILE="$pw2"
unset QA_EPHEMERAL_MARKER
export KEEP_QA_RUNNING=1
export SUITE_FAIL=0
qa_cleanup_ephemeral_driver_password
if [ ! -f "$pw2" ]; then
  echo "FAIL: KEEP_QA_RUNNING=1 must keep ephemeral password file" >&2
  exit 1
fi
rm -f "$pw2"

echo "EPHEMERAL_PASSWORD_CLEANUP_SELFTEST_OK"
exit 0
