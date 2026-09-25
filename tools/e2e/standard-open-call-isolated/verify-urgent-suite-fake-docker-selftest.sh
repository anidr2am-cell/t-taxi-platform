#!/bin/bash
# Docker-assert path only: fake runner exits 2 (pass), 1/125 (fail). Does not use real docker.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FAKE="$ROOT/test/fixtures/fake-docker-for-verify.sh"
chmod +x "$FAKE" 2>/dev/null || true

# shellcheck source=verify-urgent-suite-lib.sh
source "$ROOT/verify-urgent-suite-lib.sh"

ASSERT_NODE_IMAGE="${VERIFY_ASSERT_NODE_IMAGE:-tride-staging-tride-backend:latest}"
export ROOT ASSERT_NODE_IMAGE
export VERIFY_DOCKER_BIN="$FAKE"
export VERIFY_FORCE_DOCKER_ASSERT=1

run_one() {
  local label="$1"
  local fake_exit="$2"
  local expect_ok="$3"
  export FAKE_DOCKER_EXIT="$fake_exit"
  if [ "$expect_ok" = "yes" ]; then
    assert_expect_usage_exit assert-urgent-contact-dispatch-matrix.cjs
    echo "FAKE_DOCKER_CASE_PASS label=$label fakeExit=$fake_exit"
  else
    set +e
    ( assert_expect_usage_exit assert-urgent-contact-dispatch-matrix.cjs )
    local ec=$?
    set -e
    if [ "$ec" -eq 0 ]; then
      echo "FAIL: fake exit $fake_exit expected verify fail, got success" >&2
      exit 1
    fi
    echo "FAKE_DOCKER_CASE_FAIL_OK label=$label fakeExit=$fake_exit verifyExit=$ec"
  fi
}

echo "FAKE_DOCKER_SELFTEST_BEGIN runner=$VERIFY_DOCKER_BIN"
run_one exit2-pass 2 yes
run_one exit1-fail 1 no
run_one exit125-fail 125 no
echo "FAKE_DOCKER_SELFTEST_OK"
