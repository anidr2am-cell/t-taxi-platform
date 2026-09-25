#!/bin/bash
# gate=false: fixture + API open-list checks for driver web UI manual pass.
# KEEP_QA_RUNNING=1 keeps API/DB up after success for Flutter (default: teardown on exit).
set -euo pipefail

ROOT="${ROOT:-/opt/t-ride/releases/qa-standard-open-call}"
BACKEND_ROOT="${BACKEND_ROOT:-/opt/t-ride/releases/qa-backend-src}"
export ROOT BACKEND_ROOT
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$ROOT/ui-gate-false-$STAMP"

# shellcheck source=qa-ui-common.sh
source "$ROOT/qa-ui-common.sh"
trap qa_ui_on_exit EXIT

mkdir -p "$OUT"
cd "$ROOT"
chmod +x qa-ui-common.sh stop-qa-ui.sh 2>/dev/null || true
sed -i 's/\r$//' *.sh 2>/dev/null || true

qa_ui_require_tools "$ROOT" "$BACKEND_ROOT"

docker rm -f tride-qa-admin-api tride-qa-oc-true-api 2>/dev/null || true

./reset-db.sh | tee "$OUT/reset-db.log"
./start-api.sh false | tee "$OUT/start-api.log"

CONTAINER=tride-qa-admin-api
qa_ui_assert_port_and_network "$CONTAINER"
qa_ui_apply_patch_and_verify "$CONTAINER" "$BACKEND_ROOT" "$ROOT" | tee "$OUT/patch-verify.log"

docker cp "$ROOT/qa-ui-driver-auth.cjs" "$CONTAINER:/srv/tride/backend/qa-ui-driver-auth.cjs"
docker cp "$ROOT/run-ui-fixture.cjs" "$CONTAINER:/srv/tride/backend/run-ui-fixture.cjs"
docker cp "$ROOT/run-ui-api-verify.cjs" "$CONTAINER:/srv/tride/backend/run-ui-api-verify.cjs"
qa_ui_sync_driver_password "$CONTAINER" "$ROOT"

docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -w /srv/tride/backend "$CONTAINER" \
  env UI_MANIFEST_PATH=/srv/tride/backend/ui-manifest.json CONTACT_CONNECTION_REQUIRED=false \
  node run-ui-fixture.cjs 2>&1 | tee "$OUT/ui-fixture.log"

docker cp "$CONTAINER:/srv/tride/backend/ui-manifest.json" "$OUT/ui-manifest.json"

docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -w /srv/tride/backend "$CONTAINER" \
  env UI_MANIFEST=/srv/tride/backend/ui-manifest.json UI_VERIFY_PHASE=full \
  node run-ui-api-verify.cjs 2>&1 | tee "$OUT/ui-api-verify.json"
VERIFY_EXIT="${PIPESTATUS[0]}"
if [ "$VERIFY_EXIT" -ne 0 ]; then
  qa_ui_fail "ui-api-verify exit=$VERIFY_EXIT (see $OUT/ui-api-verify.json)"
fi

QA_UI_SUCCESS=true
echo "UI_GATE_FALSE_API_PASS out=$OUT" | tee "$OUT/summary.txt"

if [ "${KEEP_QA_RUNNING:-0}" = "1" ]; then
  qa_ui_print_keep_instructions "$OUT" "gate=false" "$CONTAINER"
  trap - EXIT
  exit 0
fi
