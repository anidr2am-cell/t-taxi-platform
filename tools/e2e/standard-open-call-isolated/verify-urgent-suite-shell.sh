#!/bin/bash
# Pre-suite checks for run-urgent-isolated-suite.sh (no QA API/DB, no real JWT/passwords).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# shellcheck source=urgent-suite-token-validate.sh
source "$ROOT/urgent-suite-token-validate.sh"
# shellcheck source=verify-urgent-suite-lib.sh
source "$ROOT/verify-urgent-suite-lib.sh"

ASSERT_NODE_IMAGE="${VERIFY_ASSERT_NODE_IMAGE:-${BACKEND_IMAGE:-tride-staging-tride-backend:latest}}"

bash -n run-urgent-isolated-suite.sh
bash -n run-urgent-isolated-lib.sh
bash -n urgent-suite-token-validate.sh
bash -n verify-urgent-suite-lib.sh
bash -n qa-cleanup-ephemeral-driver-password.sh
bash -n verify-urgent-gate-false-password-env-selftest.sh
bash -n verify-qa-ephemeral-password-cleanup-selftest.sh
verify_urgent_shell_no_bare_node

if grep -q 'console.log.*accessToken' run-urgent-isolated-suite.sh; then
  echo "FAIL: suite must not log accessToken" >&2
  exit 1
fi

if grep -E 'QA_DRIVER_JWT="\$\(driver_login' run-urgent-isolated-suite.sh; then
  echo "FAIL: QA_DRIVER_JWT must not capture driver_login stdout directly" >&2
  exit 1
fi

if [ -f "$ROOT/socket-qa/node_modules/socket.io-client/package.json" ]; then
  echo "SOCKET_DEPENDENCY_PRESENT=true"
else
  echo "SOCKET_DEPENDENCY_PRESENT=false"
  echo "FAIL: socket-qa node_modules missing — run: cd $ROOT/socket-qa && npm ci" >&2
  exit 1
fi

FAKE_GOOD='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMSJ9.fake-signature-part'
FAKE_JSON='{"httpStatus":200}'
FAKE_LF=$'eyJhbGciOiJIUzI1NiJ9.part\ncontaminated'
FAKE_CR=$'eyJhbGciOiJIUzI1NiJ9.part\rcontaminated'
FAKE_SPACE='eyJhbGciOiJIUzI1NiJ9.part with-space'

validate_bearer_token fake-good "$FAKE_GOOD" || exit 1

expect_token_reject() {
  local name="$1"
  local val="$2"
  if validate_bearer_token "reject-$name" "$val" 2>/dev/null; then
    echo "FAIL: should reject token case: $name" >&2
    exit 1
  fi
}

expect_token_reject empty ''
expect_token_reject json "$FAKE_JSON"
expect_token_reject internal-lf "$FAKE_LF"
expect_token_reject cr "$FAKE_CR"
expect_token_reject space "$FAKE_SPACE"

assert_expect_usage_exit assert-urgent-contact-dispatch-matrix.cjs
assert_expect_usage_exit assert-urgent-gate-false-smoke.cjs

run_verify_helper_paths

bash "$ROOT/verify-urgent-gate-false-password-env-selftest.sh"
bash "$ROOT/verify-qa-ephemeral-password-cleanup-selftest.sh"

echo "VERIFY_URGENT_SUITE_SHELL_OK"
exit 0
