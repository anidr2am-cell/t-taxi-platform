#!/bin/bash
# gate=false run_container_json must include QA_CONTAINER_DRIVER_PW_ENV (no secret in logs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FAKE="$ROOT/test/fixtures/fake-docker-record-exec.sh"
TMP_OUT="$(mktemp -d 2>/dev/null || mktemp -d -t urgent-pw-env.XXXX)"
chmod +x "$FAKE" 2>/dev/null || true

export OUT="$TMP_OUT"
export QA="$ROOT"
export QA_CUSTOMER_JWT=unused
export QA_SOCKET_ORIGIN=http://127.0.0.1:3000
export SOCKET_BACKEND_ROOT=/srv/tride/backend
export QA_SOCKET_DRIVER_PHONE=1111111002
export FAKE_DOCKER_ARGV_FILE="$TMP_OUT/docker-exec.argv"

# shellcheck source=run-urgent-isolated-lib.sh
source "$ROOT/run-urgent-isolated-lib.sh"

docker() {
  "$FAKE" "$@"
}

QA_CONTAINER_DRIVER_PW_ENV=( -e QA_DRIVER_PASSWORD_FILE=/srv/tride/backend/.qa-driver-password )

run_urgent_gate_false_smoke_json fake-container \
  "$OUT/urgent-gate-false-smoke.json" \
  "$OUT/urgent-gate-false-smoke.stderr.log"

if ! grep -qx -- '-e' "$FAKE_DOCKER_ARGV_FILE"; then
  echo "FAIL: docker exec missing -e" >&2
  exit 1
fi
if ! grep -qx 'QA_DRIVER_PASSWORD_FILE=/srv/tride/backend/.qa-driver-password' "$FAKE_DOCKER_ARGV_FILE"; then
  echo "FAIL: gate=false docker exec missing QA_DRIVER_PASSWORD_FILE env option" >&2
  exit 1
fi
if grep -q 'QA_DRIVER_PASSWORD=' "$FAKE_DOCKER_ARGV_FILE"; then
  echo "FAIL: unexpected QA_DRIVER_PASSWORD value in recorded argv" >&2
  exit 1
fi
if [ -s "$OUT/urgent-gate-false-smoke.stderr.log" ] && grep -qi 'QA_DRIVER_PASSWORD=' "$OUT/urgent-gate-false-smoke.stderr.log"; then
  echo "FAIL: stderr must not mention password env values" >&2
  exit 1
fi

printf '%s\n' '{"cases":{},"fatal":"qa_password_missing:{\"kind\":\"qa_password_missing\",\"stage\":\"gate_false_smoke\"}","pass":false}' \
  >"$OUT/urgent-gate-false-smoke.json"
FAIL_FILE="$OUT/FAIL.smoke-gate-false"
write_urgent_fail_artifact "$FAIL_FILE" "smoke_gate_false" 1 \
  "$OUT/urgent-gate-false-smoke.json" "$OUT/urgent-gate-false-smoke.stderr.log"
if grep -E 'QA_DRIVER_PASSWORD=|QaDriverTest' "$FAIL_FILE"; then
  echo "FAIL: FAIL artifact must not contain password values" >&2
  rm -rf "$TMP_OUT"
  exit 1
fi

echo "GATE_FALSE_PASSWORD_ENV_SELFTEST_OK"
rm -rf "$TMP_OUT"
exit 0
