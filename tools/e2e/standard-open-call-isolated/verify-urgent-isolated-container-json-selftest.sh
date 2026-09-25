#!/bin/bash
# Selftest: run_container_json captures exit 1 under set -e and writes FAIL artifact.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FAKE="$ROOT/test/fixtures/fake-docker-exec-fail.sh"
TMP_OUT="$(mktemp -d 2>/dev/null || mktemp -d -t urgent-out.XXXX)"
chmod +x "$FAKE" 2>/dev/null || true

export OUT="$TMP_OUT"
export QA="$ROOT"

# shellcheck source=run-urgent-isolated-lib.sh
source "$ROOT/run-urgent-isolated-lib.sh"

docker() {
  "$FAKE" "$@"
}

CONTAINER=fake-container
STDOUT="$OUT/matrix.json"
STDERR="$OUT/matrix.stderr.log"
touch "$STDOUT" "$STDERR"

run_container_json "$CONTAINER" "$STDOUT" "$STDERR" \
  -w /srv/tride/backend/socket-qa -- \
  node run-urgent-contact-dispatch-matrix.mjs

if [ "$RUN_CONTAINER_JSON_EC" -ne 1 ]; then
  echo "FAIL: expected RUN_CONTAINER_JSON_EC=1 got $RUN_CONTAINER_JSON_EC" >&2
  exit 1
fi

FAIL_FILE="$OUT/FAIL.matrix-gate-true"
write_urgent_fail_artifact "$FAIL_FILE" "matrix_gate_true_selftest" "$RUN_CONTAINER_JSON_EC" "$STDOUT" "$STDERR"

if [ ! -f "$FAIL_FILE" ]; then
  echo "FAIL: missing $FAIL_FILE" >&2
  exit 1
fi

echo "CONTAINER_JSON_SELFTEST_OK ec=$RUN_CONTAINER_JSON_EC failFile=$FAIL_FILE"
rm -rf "$TMP_OUT"
exit 0
