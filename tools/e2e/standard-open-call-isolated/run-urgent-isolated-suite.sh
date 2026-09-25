#!/bin/bash
# Isolated URGENT E2E: gate=true contact-deferred dispatch + gate=false smoke.
set -euo pipefail

_SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=urgent-suite-token-validate.sh
source "$_SUITE_DIR/urgent-suite-token-validate.sh"
# shellcheck source=run-urgent-isolated-lib.sh
source "$_SUITE_DIR/run-urgent-isolated-lib.sh"

QA="${QA:-/opt/t-ride/releases/qa-standard-open-call}"
BR="${BACKEND_ROOT:-/opt/t-ride/releases/qa-backend-src}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$QA/urgent-isolated-$STAMP"
CONTAINER_GATE_TRUE="${CONTAINER_GATE_TRUE:-tride-qa-oc-true-api}"
CONTAINER_GATE_FALSE="${CONTAINER_GATE_FALSE:-tride-qa-admin-api}"
DRIVER_PHONE="${QA_SOCKET_DRIVER_PHONE:-1111111002}"
HEALTH_ATTEMPTS="${HEALTH_ATTEMPTS:-30}"
HEALTH_SLEEP_SEC="${HEALTH_SLEEP_SEC:-2}"
KEEP_QA_RUNNING="${KEEP_QA_RUNNING:-0}"

SUITE_FAIL=0
SUITE_FAIL_REASON=""
QA_CONTAINER_DRIVER_PW_ENV=()

mkdir -p "$OUT"
cd "$QA"
chmod +x reset-db.sh start-api-internal.sh apply-backend-patch.sh verify-backend-patch.sh 2>/dev/null || true
sed -i 's/\r$//' "$QA"/*.sh 2>/dev/null || true

fail_suite() {
  SUITE_FAIL=1
  SUITE_FAIL_REASON="${1:-unknown}"
  echo "FAIL: $SUITE_FAIL_REASON" | tee "$OUT/FAIL.suite"
  exit 1
}

cleanup_qa() {
  local ec=$?
  if [ "$SUITE_FAIL" -eq 1 ]; then
    ec=1
  fi
  if [ "$KEEP_QA_RUNNING" = "1" ] && [ "$ec" -eq 0 ]; then
    exit 0
  fi
  # shellcheck source=qa-cleanup-ephemeral-driver-password.sh
  source "$_SUITE_DIR/qa-cleanup-ephemeral-driver-password.sh"
  QA_EPHEMERAL_MARKER="$QA/.qa-ephemeral-password-file.path"
  qa_cleanup_ephemeral_driver_password
  docker rm -f tride-qa-admin-api tride-qa-oc-true-api 2>/dev/null || true
  docker stop tride-qa-admin-db 2>/dev/null || true
  exit "$ec"
}
trap cleanup_qa EXIT

wait_api_healthy() {
  local name="$1"
  local i
  for i in $(seq 1 "$HEALTH_ATTEMPTS"); do
    if docker exec "$name" wget -qO- http://127.0.0.1:3000/api/v1/health 2>/dev/null \
      | grep -q '"database":"connected"'; then
      echo "API healthy ($name) attempt=$i"
      return 0
    fi
    sleep "$HEALTH_SLEEP_SEC"
  done
  echo "FAIL: API health timeout container=$name" >&2
  return 1
}

require_host_node_in_container() {
  local c="$1"
  if ! docker exec "$c" node -e "process.exit(0)" >/dev/null 2>&1; then
    fail_suite "container $c has no node"
  fi
}

require_host_socket_qa_bundle() {
  if [ ! -f "$QA/socket-qa/package.json" ]; then
    fail_suite "missing $QA/socket-qa/package.json"
  fi
  if [ ! -f "$QA/socket-qa/node_modules/socket.io-client/package.json" ]; then
    echo "FAIL: socket-qa node_modules not bundled — on the deploy host run:" >&2
    echo "  cd $QA/socket-qa && npm ci" >&2
    fail_suite "socket-qa node_modules missing (no in-container npm install)"
  fi
}

require_container_socket_qa() {
  local c="$1"
  if ! docker exec "$c" test -f /srv/tride/backend/socket-qa/node_modules/socket.io-client/package.json; then
    fail_suite "container $c missing socket.io-client (copy socket-qa with node_modules first)"
  fi
}

# Log stdout+stderr to file; return exit code of command (not tee).
run_logged() {
  local log="$1"
  shift
  set +e
  "$@" >>"$log" 2>&1
  local ec=$?
  set -e
  return "$ec"
}

load_mint_token() {
  local container="$1"
  local role="$2"
  local out_var="$3"
  local tok=""
  set +e
  tok="$(docker exec "$container" node -pe \
    "JSON.parse(require('fs').readFileSync('/srv/tride/backend/.qa-tokens.json','utf8')).$role" 2>/dev/null)"
  local ec=$?
  set -e
  if [ "$ec" -ne 0 ]; then
    echo "FAIL: read mint token role=$role exit=$ec" >&2
    return 1
  fi
  tok="$(printf '%s' "$tok" | tr -d '\r\n')"
  if ! validate_bearer_token "mint-$role" "$tok"; then
    return 1
  fi
  printf -v "$out_var" '%s' "$tok"
  return 0
}

driver_login_prepare() {
  local container="$1"
  qa_sync_driver_password_to_container "$container" "$QA"
  set +e
  docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -e QA_DRIVER_PHONE="$DRIVER_PHONE" -w /srv/tride/backend "$container" node -e "
const fs = require('fs');
const { loginDriverApi } = require('./qa-ui-driver-auth.cjs');
(async () => {
  const phone = process.env.QA_DRIVER_PHONE || '1111111002';
  const r = await loginDriverApi('http://127.0.0.1:3000/api/v1', phone);
  fs.writeFileSync('/srv/tride/backend/.qa-driver-login-meta.json', JSON.stringify({
    httpStatus: r.httpStatus,
    errorCode: r.errorCode,
    loginPass: r.loginOk,
  }));
  if (!r.loginOk || !r.accessToken) process.exit(1);
  fs.writeFileSync('/srv/tride/backend/.qa-driver-login-token', r.accessToken, { mode: 0o600 });
  process.exit(0);
})().catch(() => process.exit(1));
" >>"$OUT/driver-login.log" 2>&1
  local ec=$?
  set -e
  docker exec "$container" cat /srv/tride/backend/.qa-driver-login-meta.json >>"$OUT/driver-login.log" 2>/dev/null || true
  return "$ec"
}

driver_login_load_token() {
  local container="$1"
  local out_var="$2"
  local tok=""
  set +e
  tok="$(docker exec "$container" cat /srv/tride/backend/.qa-driver-login-token 2>/dev/null)"
  local ec=$?
  set -e
  if [ "$ec" -ne 0 ]; then
    echo "FAIL: read driver login token file exit=$ec" >&2
    return 1
  fi
  tok="$(printf '%s' "$tok" | tr -d '\r\n')"
  if ! validate_bearer_token "driver-login" "$tok"; then
    return 1
  fi
  printf -v "$out_var" '%s' "$tok"
  return 0
}

driver_login_http_status() {
  local container="$1"
  docker exec "$container" node -pe \
    "JSON.parse(require('fs').readFileSync('/srv/tride/backend/.qa-driver-login-meta.json','utf8')).httpStatus"
}

copy_qa_scripts() {
  local c="$1"
  urgent_docker_cp_required "$QA" "$c" run-socket-fixture.cjs /srv/tride/backend/run-socket-fixture.cjs
  urgent_docker_cp_required "$QA" "$c" qa-ui-driver-auth.cjs /srv/tride/backend/qa-ui-driver-auth.cjs
  urgent_docker_cp_required "$QA" "$c" qa-driver-password.cjs /srv/tride/backend/qa-driver-password.cjs
  urgent_docker_cp_required "$QA" "$c" urgent-qa-pickup.cjs /srv/tride/backend/urgent-qa-pickup.cjs
  urgent_docker_cp_required "$QA" "$c" urgent-booking-body.cjs /srv/tride/backend/urgent-booking-body.cjs
  urgent_docker_cp_required "$QA" "$c" urgent-qa-http-report.cjs /srv/tride/backend/urgent-qa-http-report.cjs
  urgent_docker_cp_required "$QA" "$c" urgent-qa-db-markers.cjs /srv/tride/backend/urgent-qa-db-markers.cjs
  urgent_docker_cp_required "$QA" "$c" urgent-qa-db-errors.cjs /srv/tride/backend/urgent-qa-db-errors.cjs
  urgent_docker_cp_required "$QA" "$c" mint-qa-tokens.cjs /srv/tride/backend/mint-qa-tokens.cjs
  docker cp "$QA/socket-qa" "$c:/srv/tride/backend/socket-qa"
  require_container_socket_qa "$c"
  verify_urgent_qa_helpers_in_container "$QA" "$c" "$OUT/helper-verify-${c}.json.log"
}

seed_socket_fixture() {
  local c="$1"
  local gate_flag="$2"
  qa_sync_driver_password_to_container "$c" "$QA"
  run_logged "$OUT/fixture-seed-${gate_flag}.log" \
    docker exec "${QA_CONTAINER_DRIVER_PW_ENV[@]}" -w /srv/tride/backend "$c" \
    env QA_DRIVER_USER_ID=11 SOCKET_DRIVER_USER_ID=11 "CONTACT_CONNECTION_REQUIRED=$gate_flag" \
    node run-socket-fixture.cjs
}

mint_admin_customer_tokens() {
  local c="$1"
  run_logged "$OUT/mint.log" \
    docker exec -w /srv/tride/backend "$c" env QA_DRIVER_USER_ID=11 node mint-qa-tokens.cjs
}

apply_patch() {
  local c="$1"
  run_logged "$OUT/apply-patch-${c}.log" ./apply-backend-patch.sh "$c" "$BR"
  docker restart "$c" >>"$OUT/apply-patch-${c}.log" 2>&1
  wait_api_healthy "$c"
  run_logged "$OUT/patch-verify-${c}.log" env BACKEND_ROOT="$BR" ./verify-backend-patch.sh "$c" "$BR"
}

require_host_socket_qa_bundle

echo "executedAtUtc=$STAMP scope=urgent_isolated_e2e" | tee "$OUT/meta.txt"
echo "backendRoot=$BR driverPhone=$DRIVER_PHONE" | tee -a "$OUT/meta.txt"

docker rm -f tride-qa-admin-api tride-qa-oc-true-api 2>/dev/null || true

echo "=== gate=true URGENT contact-dispatch matrix ===" | tee "$OUT/run.log"
run_logged "$OUT/reset-db-gate-true.log" ./reset-db.sh
run_logged "$OUT/start-api-gate-true.log" ./start-api-internal.sh true
apply_patch "$CONTAINER_GATE_TRUE"
require_host_node_in_container "$CONTAINER_GATE_TRUE"
copy_qa_scripts "$CONTAINER_GATE_TRUE"
seed_socket_fixture "$CONTAINER_GATE_TRUE" true || fail_suite "fixture seed gate=true"
mint_admin_customer_tokens "$CONTAINER_GATE_TRUE" || fail_suite "mint tokens gate=true"

QA_ADMIN_JWT=""
QA_CUSTOMER_JWT=""
QA_DRIVER_JWT=""
load_mint_token "$CONTAINER_GATE_TRUE" admin QA_ADMIN_JWT || fail_suite "load admin token gate=true"
load_mint_token "$CONTAINER_GATE_TRUE" customer QA_CUSTOMER_JWT || fail_suite "load customer token gate=true"
driver_login_prepare "$CONTAINER_GATE_TRUE" || fail_suite "driver login gate=true"
driver_login_load_token "$CONTAINER_GATE_TRUE" QA_DRIVER_JWT || fail_suite "load driver token gate=true"
QA_DRIVER_LOGIN_HTTP_STATUS="$(driver_login_http_status "$CONTAINER_GATE_TRUE")"
if [ "$QA_DRIVER_LOGIN_HTTP_STATUS" != "200" ]; then
  fail_suite "driver login httpStatus=$QA_DRIVER_LOGIN_HTTP_STATUS (expected 200)"
fi
export QA_ADMIN_JWT QA_CUSTOMER_JWT QA_DRIVER_JWT QA_DRIVER_LOGIN_HTTP_STATUS
export QA_DRIVER_AUTH_MODE=post_auth_login
export QA_SOCKET_ORIGIN=http://127.0.0.1:3000
export SOCKET_BACKEND_ROOT=/srv/tride/backend

run_container_json "$CONTAINER_GATE_TRUE" \
  "$OUT/urgent-matrix-gate-true.json" \
  "$OUT/urgent-matrix-gate-true.stderr.log" \
  -e QA_ADMIN_JWT -e QA_CUSTOMER_JWT -e QA_DRIVER_JWT \
  -e QA_SOCKET_ORIGIN -e SOCKET_BACKEND_ROOT \
  -e QA_DRIVER_LOGIN_HTTP_STATUS -e QA_DRIVER_AUTH_MODE \
  -w /srv/tride/backend/socket-qa -- \
  node run-urgent-contact-dispatch-matrix.mjs
MATRIX_GT_EXIT=$RUN_CONTAINER_JSON_EC
echo "urgentMatrixGateTrueExit=$MATRIX_GT_EXIT out=$OUT" | tee -a "$OUT/run.log"
if [ "$MATRIX_GT_EXIT" -ne 0 ]; then
  write_urgent_fail_artifact "$OUT/FAIL.matrix-gate-true" "matrix_gate_true" "$MATRIX_GT_EXIT" \
    "$OUT/urgent-matrix-gate-true.json" "$OUT/urgent-matrix-gate-true.stderr.log"
  fail_suite "urgent gate=true matrix node exit=$MATRIX_GT_EXIT"
fi
assert_json_in_container "$CONTAINER_GATE_TRUE" \
  "$QA/assert-urgent-contact-dispatch-matrix.cjs" \
  "$OUT/urgent-matrix-gate-true.json" \
  "$OUT/urgent-matrix-assert.log"
if [ "$ASSERT_JSON_IN_CONTAINER_EC" -ne 0 ]; then
  write_urgent_fail_artifact "$OUT/FAIL.matrix-assert-gate-true" "matrix_assert_gate_true" "$ASSERT_JSON_IN_CONTAINER_EC" \
    "$OUT/urgent-matrix-gate-true.json" "$OUT/urgent-matrix-assert.stderr.log"
  fail_suite "urgent gate=true matrix JSON assert exit=$ASSERT_JSON_IN_CONTAINER_EC"
fi

docker rm -f "$CONTAINER_GATE_TRUE" 2>/dev/null || true

echo "=== gate=false URGENT smoke ===" | tee -a "$OUT/run.log"
run_logged "$OUT/reset-db-gate-false.log" ./reset-db.sh
run_logged "$OUT/start-api-gate-false.log" ./start-api-internal.sh false
apply_patch "$CONTAINER_GATE_FALSE"
require_host_node_in_container "$CONTAINER_GATE_FALSE"
copy_qa_scripts "$CONTAINER_GATE_FALSE"
seed_socket_fixture "$CONTAINER_GATE_FALSE" false || fail_suite "fixture seed gate=false"
mint_admin_customer_tokens "$CONTAINER_GATE_FALSE" || fail_suite "mint tokens gate=false"

QA_CUSTOMER_JWT=""
load_mint_token "$CONTAINER_GATE_FALSE" customer QA_CUSTOMER_JWT || fail_suite "load customer token gate=false"
export QA_CUSTOMER_JWT
export QA_SOCKET_DRIVER_PHONE="$DRIVER_PHONE"
export QA_SOCKET_ORIGIN=http://127.0.0.1:3000
export SOCKET_BACKEND_ROOT=/srv/tride/backend

qa_sync_driver_password_to_container "$CONTAINER_GATE_FALSE" "$QA"
qa_require_container_driver_password "$CONTAINER_GATE_FALSE"
run_urgent_gate_false_smoke_json "$CONTAINER_GATE_FALSE" \
  "$OUT/urgent-gate-false-smoke.json" \
  "$OUT/urgent-gate-false-smoke.stderr.log"
SMOKE_EXIT=$RUN_CONTAINER_JSON_EC
echo "urgentGateFalseSmokeExit=$SMOKE_EXIT out=$OUT" | tee -a "$OUT/run.log"
if [ "$SMOKE_EXIT" -ne 0 ]; then
  write_urgent_fail_artifact "$OUT/FAIL.smoke-gate-false" "smoke_gate_false" "$SMOKE_EXIT" \
    "$OUT/urgent-gate-false-smoke.json" "$OUT/urgent-gate-false-smoke.stderr.log"
  fail_suite "urgent gate=false smoke node exit=$SMOKE_EXIT"
fi
assert_json_in_container "$CONTAINER_GATE_FALSE" \
  "$QA/assert-urgent-gate-false-smoke.cjs" \
  "$OUT/urgent-gate-false-smoke.json" \
  "$OUT/urgent-gate-false-assert.log"
if [ "$ASSERT_JSON_IN_CONTAINER_EC" -ne 0 ]; then
  write_urgent_fail_artifact "$OUT/FAIL.smoke-assert-gate-false" "smoke_assert_gate_false" "$ASSERT_JSON_IN_CONTAINER_EC" \
    "$OUT/urgent-gate-false-smoke.json" "$OUT/urgent-gate-false-assert.stderr.log"
  fail_suite "urgent gate=false smoke JSON assert exit=$ASSERT_JSON_IN_CONTAINER_EC"
fi

echo "URGENT_ISOLATED_PASS out=$OUT driverLoginHttp=$QA_DRIVER_LOGIN_HTTP_STATUS" | tee "$OUT/summary.txt"
exit 0
