#!/bin/bash
# gate=true POST: admin contact verify + API post checks (run while PRE QA API is still up).
set -euo pipefail

ROOT="${ROOT:-/opt/t-ride/releases/qa-standard-open-call}"
export ROOT
OUT="${1:-$(cat "$ROOT/.ui-gate-true-last-out" 2>/dev/null || true)}"
CONTAINER="${UI_QA_CONTAINER:-tride-qa-oc-true-api}"

# shellcheck source=qa-ui-common.sh
source "$ROOT/qa-ui-common.sh"
trap qa_ui_on_exit EXIT

if [ -z "$OUT" ] || [ ! -d "$OUT" ]; then
  qa_ui_fail "usage: run-driver-ui-gate-true-post.sh <ui-gate-true-OUT_DIR> (run pre first)"
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  qa_ui_fail "container $CONTAINER not running — re-run run-driver-ui-gate-true-pre.sh with KEEP_QA_RUNNING=1"
fi

cd "$ROOT"
sed -i 's/\r$//' *.sh 2>/dev/null || true

if [ -z "${QA_DRIVER_PASSWORD:-}" ] && [ -z "${QA_DRIVER_PASSWORD_FILE:-}" ] && [ -f "$OUT/qa-driver-password-file.path" ]; then
  QA_DRIVER_PASSWORD_FILE="$(tr -d '\r\n' <"$OUT/qa-driver-password-file.path")"
  export QA_DRIVER_PASSWORD_FILE
fi

if [ ! -f "$ROOT/run-ui-gate-true-verify-post.cjs" ]; then
  qa_ui_fail "missing run-ui-gate-true-verify-post.cjs"
fi

docker cp "$ROOT/run-ui-gate-true-verify-post.cjs" "$CONTAINER:/srv/tride/backend/run-ui-gate-true-verify-post.cjs"
docker cp "$ROOT/run-ui-api-verify.cjs" "$CONTAINER:/srv/tride/backend/run-ui-api-verify.cjs"
qa_ui_sync_driver_password "$CONTAINER" "$ROOT"

docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -w /srv/tride/backend "$CONTAINER" \
  node run-ui-gate-true-verify-post.cjs 2>&1 | tee "$OUT/ui-verify-post.json"
VERIFY_HTTP_EXIT="${PIPESTATUS[0]}"
if [ "$VERIFY_HTTP_EXIT" -ne 0 ]; then
  qa_ui_fail "admin contact verify failed exit=$VERIFY_HTTP_EXIT"
fi

docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -w /srv/tride/backend "$CONTAINER" \
  env UI_MANIFEST=/srv/tride/backend/ui-manifest.json UI_VERIFY_PHASE=post \
  node run-ui-api-verify.cjs 2>&1 | tee "$OUT/ui-api-post.json"
POST_EXIT="${PIPESTATUS[0]}"
if [ "$POST_EXIT" -ne 0 ]; then
  qa_ui_fail "ui-api-verify post exit=$POST_EXIT"
fi

QA_UI_SUCCESS=true
echo "UI_GATE_TRUE_POST_PASS out=$OUT" | tee -a "$OUT/summary.txt"

if [ "${KEEP_QA_RUNNING:-0}" = "1" ]; then
  qa_ui_print_keep_instructions "$OUT" "gate=true POST (after verify)" "$CONTAINER"
  trap - EXIT
  exit 0
fi
