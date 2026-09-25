#!/bin/bash
# gate=true: fixture + PRE API checks only — stops before admin contact verify for manual UI.
set -euo pipefail

ROOT="${ROOT:-/opt/t-ride/releases/qa-standard-open-call}"
BACKEND_ROOT="${BACKEND_ROOT:-/opt/t-ride/releases/qa-backend-src}"
export ROOT BACKEND_ROOT
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$ROOT/ui-gate-true-$STAMP"

# shellcheck source=qa-ui-common.sh
source "$ROOT/qa-ui-common.sh"
trap qa_ui_on_exit EXIT

mkdir -p "$OUT"
cd "$ROOT"
chmod +x qa-ui-common.sh stop-qa-ui.sh run-driver-ui-gate-true-post.sh 2>/dev/null || true
sed -i 's/\r$//' *.sh 2>/dev/null || true

qa_ui_require_tools "$ROOT" "$BACKEND_ROOT"
if [ ! -f "$ROOT/run-ui-gate-true-verify-post.cjs" ]; then
  qa_ui_fail "missing run-ui-gate-true-verify-post.cjs"
fi

docker rm -f tride-qa-admin-api tride-qa-oc-true-api 2>/dev/null || true

./reset-db.sh | tee "$OUT/reset-db.log"
./start-api.sh true | tee "$OUT/start-api.log"

CONTAINER=tride-qa-oc-true-api
qa_ui_assert_port_and_network "$CONTAINER"
qa_ui_apply_patch_and_verify "$CONTAINER" "$BACKEND_ROOT" "$ROOT" | tee "$OUT/patch-verify.log"

docker cp "$ROOT/qa-ui-driver-auth.cjs" "$CONTAINER:/srv/tride/backend/qa-ui-driver-auth.cjs"
docker cp "$ROOT/run-ui-fixture.cjs" "$CONTAINER:/srv/tride/backend/run-ui-fixture.cjs"
docker cp "$ROOT/run-ui-api-verify.cjs" "$CONTAINER:/srv/tride/backend/run-ui-api-verify.cjs"
docker cp "$ROOT/run-ui-gate-true-verify-post.cjs" "$CONTAINER:/srv/tride/backend/run-ui-gate-true-verify-post.cjs"
qa_ui_sync_driver_password "$CONTAINER" "$ROOT"
if [ -n "${QA_DRIVER_PASSWORD_FILE:-}" ] && [ -z "${QA_DRIVER_PASSWORD:-}" ]; then
  printf '%s\n' "$QA_DRIVER_PASSWORD_FILE" >"$OUT/qa-driver-password-file.path"
fi

docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -w /srv/tride/backend "$CONTAINER" \
  env UI_MANIFEST_PATH=/srv/tride/backend/ui-manifest.json CONTACT_CONNECTION_REQUIRED=true \
  node run-ui-fixture.cjs 2>&1 | tee "$OUT/ui-fixture.log"

docker cp "$CONTAINER:/srv/tride/backend/ui-manifest.json" "$OUT/ui-manifest.json"

docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -w /srv/tride/backend "$CONTAINER" \
  env UI_MANIFEST=/srv/tride/backend/ui-manifest.json UI_VERIFY_PHASE=pre \
  node run-ui-api-verify.cjs 2>&1 | tee "$OUT/ui-api-pre.json"
PRE_EXIT="${PIPESTATUS[0]}"
if [ "$PRE_EXIT" -ne 0 ]; then
  qa_ui_fail "ui-api-verify pre exit=$PRE_EXIT"
fi

echo "$OUT" > "$ROOT/.ui-gate-true-last-out"
echo "$CONTAINER" > "$ROOT/.ui-gate-true-container"

QA_UI_SUCCESS=true
echo "UI_GATE_TRUE_PRE_PASS out=$OUT" | tee "$OUT/summary.txt"
echo "Next (after manual Flutter pre checks): KEEP_QA_RUNNING=1 bash $ROOT/run-driver-ui-gate-true-post.sh $OUT"

if [ "${KEEP_QA_RUNNING:-0}" = "1" ]; then
  qa_ui_print_keep_instructions "$OUT" "gate=true PRE (pending customer hidden)" "$CONTAINER"
  echo "Post-verify when ready:"
  echo "  KEEP_QA_RUNNING=1 bash $ROOT/run-driver-ui-gate-true-post.sh $OUT"
  trap - EXIT
  exit 0
fi
