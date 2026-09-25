# shellcheck shell=bash
# Shared helpers for verify-urgent-suite-shell.sh (source only).

verify_urgent_init_docker_cmd() {
  if [ -n "${VERIFY_DOCKER_BIN:-}" ]; then
    DOCKER_CMD=("$VERIFY_DOCKER_BIN")
  else
    DOCKER_CMD=(docker)
  fi
}

# Exit 0 → use Docker node; exit 1 → use host node (if available).
verify_urgent_should_use_docker_node() {
  if [ "${VERIFY_FORCE_DOCKER_ASSERT:-}" = "1" ]; then
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

verify_urgent_node_runner_label() {
  if verify_urgent_should_use_docker_node; then
    echo "docker"
  else
    echo "host-node"
  fi
}

require_docker_assert_runner() {
  verify_urgent_init_docker_cmd
  if ! command -v "${DOCKER_CMD[0]}" >/dev/null 2>&1; then
    echo "FAIL: docker runner not executable: ${DOCKER_CMD[0]}" >&2
    exit 1
  fi
  if ! "${DOCKER_CMD[@]}" image inspect "$ASSERT_NODE_IMAGE" >/dev/null 2>&1; then
    echo "FAIL: assert runner image not present locally: $ASSERT_NODE_IMAGE" >&2
    if [ -z "${VERIFY_DOCKER_BIN:-}" ]; then
      echo "      (pull/build QA backend image on this host, or set VERIFY_ASSERT_NODE_IMAGE)" >&2
    fi
    exit 1
  fi
}

# Sets named ec + stderr_file; always returns 0 (safe under set -e).
run_verify_node_docker() {
  local container_script="$1"
  local ec_out="$2"
  local stderr_out="$3"
  shift 3
  local err_file
  local cmd_ec=0

  verify_urgent_init_docker_cmd
  err_file="$(mktemp 2>/dev/null || mktemp -t verify-node-stderr.XXXXXX)"

  set +e
  "${DOCKER_CMD[@]}" run --pull=never --network none --rm \
    --entrypoint node \
    "$@" \
    "$ASSERT_NODE_IMAGE" \
    "$container_script" 2>"$err_file"
  cmd_ec=$?
  set -e

  printf -v "$ec_out" '%s' "$cmd_ec"
  printf -v "$stderr_out" '%s' "$err_file"
  return 0
}

run_verify_node_host() {
  local host_script="$1"
  local ec_out="$2"
  local stderr_out="$3"
  local err_file
  local cmd_ec=0

  err_file="$(mktemp 2>/dev/null || mktemp -t verify-node-stderr.XXXXXX)"

  set +e
  node "$host_script" 2>"$err_file"
  cmd_ec=$?
  set -e

  printf -v "$ec_out" '%s' "$cmd_ec"
  printf -v "$stderr_out" '%s' "$err_file"
  return 0
}

# Single assert .cjs mounted read-only (usage check expects exit 2).
run_verify_assert_usage() {
  local script_name="$1"
  local host_path="$ROOT/$script_name"
  local ec=-1
  local stderr_file=""

  if [ ! -f "$host_path" ]; then
    echo "FAIL: missing assert script $host_path" >&2
    exit 1
  fi

  if verify_urgent_should_use_docker_node; then
    require_docker_assert_runner
    run_verify_node_docker /assert/script.cjs ec stderr_file \
      -v "$host_path:/assert/script.cjs:ro"
    echo "VERIFY_NODE_RUNNER=docker image=$ASSERT_NODE_IMAGE script=$script_name exit=$ec"
  else
    run_verify_node_host "$host_path" ec stderr_file
    echo "VERIFY_NODE_RUNNER=host-node script=$script_name exit=$ec"
  fi

  if [ "$ec" -ne 2 ]; then
    echo "FAIL: $script_name usage exit=$ec (expected 2)" >&2
    if [ -n "$stderr_file" ] && [ -s "$stderr_file" ]; then
      echo "FAIL: runner stderr (first 20 lines):" >&2
      head -n 20 "$stderr_file" >&2 || true
    fi
    if [ -n "$stderr_file" ]; then
      rm -f "$stderr_file"
    fi
    exit 1
  fi

  if [ -n "$stderr_file" ]; then
    rm -f "$stderr_file"
  fi
  return 0
}

assert_expect_usage_exit() {
  run_verify_assert_usage "$1"
}

# verify-urgent-qa-helper-paths.cjs — read-only QA tree + writable smoke tmp.
run_verify_helper_paths() {
  local script_name="verify-urgent-qa-helper-paths.cjs"
  local host_path="$ROOT/$script_name"
  local ec=-1
  local stderr_file=""
  local smoke_tmp=""

  if [ ! -f "$host_path" ]; then
    echo "FAIL: missing $host_path" >&2
    exit 1
  fi

  if verify_urgent_should_use_docker_node; then
    require_docker_assert_runner
    smoke_tmp="$(mktemp -d 2>/dev/null || mktemp -d -t verify-smoke.XXXXXX)"
    run_verify_node_docker "/verify/root/$script_name" ec stderr_file \
      -v "$ROOT:/verify/root:ro" \
      -v "$smoke_tmp:/tmp/verify-writable:rw" \
      -e VERIFY_ROOT=/verify/root \
      -e VERIFY_SMOKE_TMP=/tmp/verify-writable
    rm -rf "$smoke_tmp"
    echo "VERIFY_NODE_RUNNER=docker image=$ASSERT_NODE_IMAGE script=$script_name exit=$ec"
  else
    run_verify_node_host "$host_path" ec stderr_file
    echo "VERIFY_NODE_RUNNER=host-node script=$script_name exit=$ec"
  fi

  if [ "$ec" -ne 0 ]; then
    echo "FAIL: $script_name exit=$ec (expected 0)" >&2
    if [ -n "$stderr_file" ] && [ -s "$stderr_file" ]; then
      echo "FAIL: runner stderr (first 30 lines):" >&2
      head -n 30 "$stderr_file" >&2 || true
    fi
    if [ -n "$stderr_file" ]; then
      rm -f "$stderr_file"
    fi
    exit 1
  fi

  if [ -n "$stderr_file" ]; then
    rm -f "$stderr_file"
  fi
  return 0
}

# verify-urgent-suite-shell.sh must not invoke host node directly.
verify_urgent_shell_no_bare_node() {
  local shell_script="$ROOT/verify-urgent-suite-shell.sh"
  local hits
  hits="$(grep -En '^[[:space:]]*node[[:space:]]' "$shell_script" || true)"
  if [ -n "$hits" ]; then
    echo "FAIL: verify-urgent-suite-shell.sh must not call host node directly:" >&2
    echo "$hits" >&2
    exit 1
  fi
  hits="$(grep -En '\|[[:space:]]*node[[:space:]]' "$shell_script" || true)"
  if [ -n "$hits" ]; then
    echo "FAIL: verify-urgent-suite-shell.sh must not pipe to node:" >&2
    echo "$hits" >&2
    exit 1
  fi
}
