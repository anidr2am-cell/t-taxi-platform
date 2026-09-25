#!/bin/bash
# Exercises run_verify_helper_paths via VERIFY_FORCE_DOCKER_ASSERT + fake docker (host node simulates container).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FAKE="$ROOT/test/fixtures/fake-docker-helper-paths.sh"
chmod +x "$FAKE" 2>/dev/null || true

# shellcheck source=verify-urgent-suite-lib.sh
source "$ROOT/verify-urgent-suite-lib.sh"

export ROOT
export ASSERT_NODE_IMAGE="${VERIFY_ASSERT_NODE_IMAGE:-tride-staging-tride-backend:latest}"
export VERIFY_DOCKER_BIN="$FAKE"
export VERIFY_FORCE_DOCKER_ASSERT=1

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: host node required to simulate docker helper-paths run"
  exit 0
fi

run_verify_helper_paths
echo "HELPER_PATHS_FAKE_DOCKER_SELFTEST_OK"
