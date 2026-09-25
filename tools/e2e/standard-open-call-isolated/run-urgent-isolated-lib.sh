# shellcheck shell=bash
# Shared run helpers for run-urgent-isolated-suite.sh (source only).

RUN_CONTAINER_JSON_EC=0
ASSERT_JSON_IN_CONTAINER_EC=0

# Always returns 0; sets RUN_CONTAINER_JSON_EC.
run_container_json() {
  local container="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3
  local -a opts=()
  local -a cmd=()
  local past_sep=0
  local cmd_ec=0

  RUN_CONTAINER_JSON_EC=0

  for arg in "$@"; do
    if [ "$arg" = "--" ]; then
      past_sep=1
      continue
    fi
    if [ "$past_sep" -eq 0 ]; then
      opts+=("$arg")
    else
      cmd+=("$arg")
    fi
  done
  if [ "${#cmd[@]}" -eq 0 ]; then
    echo "FAIL: run_container_json missing command after --" >&2
    RUN_CONTAINER_JSON_EC=2
    return 0
  fi

  if docker exec "${opts[@]}" "$container" "${cmd[@]}" >"$stdout_file" 2>"$stderr_file"; then
    cmd_ec=0
  else
    cmd_ec=$?
  fi
  RUN_CONTAINER_JSON_EC=$cmd_ec
  return 0
}

# Copy host QA file into container or fail_suite (no secrets in message).
urgent_docker_cp_required() {
  local qa_dir="$1"
  local container="$2"
  local rel="$3"
  local dest="$4"
  local host_path="$qa_dir/$rel"
  if [ ! -f "$host_path" ]; then
    if declare -F fail_suite >/dev/null 2>&1; then
      fail_suite "missing_qa_host_file:$rel"
    else
      echo "FAIL: missing_qa_host_file:$rel" >&2
      return 1
    fi
  fi
  docker cp "$host_path" "$container:$dest"
}

# After copy_qa_scripts: require helpers at /srv/tride/backend (runner requireBackend paths).
verify_urgent_qa_helpers_in_container() {
  local qa_dir="$1"
  local container="$2"
  local log_file="$3"
  local verify_script="$qa_dir/verify-urgent-qa-helpers-container.cjs"

  if [ ! -f "$verify_script" ]; then
    fail_suite "missing_qa_host_file:verify-urgent-qa-helpers-container.cjs"
  fi

  for rel in urgent-qa-db-markers.cjs urgent-qa-db-errors.cjs urgent-qa-pickup.cjs; do
    if ! docker exec "$container" test -f "/srv/tride/backend/$rel"; then
      fail_suite "urgent_qa_helper_missing_in_container container=$container file=$rel"
    fi
  done

  docker cp "$verify_script" "$container:/srv/tride/backend/verify-urgent-qa-helpers-container.cjs"
  set +e
  docker exec -w /srv/tride/backend -e SOCKET_BACKEND_ROOT=/srv/tride/backend "$container" \
    node verify-urgent-qa-helpers-container.cjs >"$log_file" 2>&1
  local ec=$?
  set -e
  if [ "$ec" -ne 0 ]; then
    fail_suite "urgent_qa_helpers_require_check_failed container=$container exit=$ec log=$(basename "$log_file")"
  fi
  return 0
}

# Never log QA_CONTAINER_DRIVER_PW_ENV values (may contain password).
qa_container_uses_direct_password_env() {
  local arg
  for arg in "${QA_CONTAINER_DRIVER_PW_ENV[@]+"${QA_CONTAINER_DRIVER_PW_ENV[@]}"}"; do
    case "$arg" in
      QA_DRIVER_PASSWORD=*) return 0 ;;
    esac
  done
  return 1
}

# File exists, mode 600, non-empty. Does not print file contents.
qa_require_container_driver_password() {
  local container="$1"
  if qa_container_uses_direct_password_env; then
    return 0
  fi
  if [ -n "${QA_DRIVER_PASSWORD:-}" ]; then
    return 0
  fi
  if ! docker exec "$container" test -f /srv/tride/backend/.qa-driver-password; then
    if declare -F fail_suite >/dev/null 2>&1; then
      fail_suite "qa_password_file_missing_in_container"
    else
      echo "FAIL: qa_password_file_missing_in_container" >&2
      return 1
    fi
  fi
  local mode
  mode="$(docker exec "$container" stat -c '%a' /srv/tride/backend/.qa-driver-password 2>/dev/null || true)"
  if [ "$mode" != "600" ]; then
    if declare -F fail_suite >/dev/null 2>&1; then
      fail_suite "qa_password_file_mode_not_600"
    else
      echo "FAIL: qa_password_file_mode_not_600" >&2
      return 1
    fi
  fi
  if ! docker exec "$container" test -s /srv/tride/backend/.qa-driver-password; then
    if declare -F fail_suite >/dev/null 2>&1; then
      fail_suite "qa_password_file_empty"
    else
      echo "FAIL: qa_password_file_empty" >&2
      return 1
    fi
  fi
  return 0
}

run_urgent_gate_false_smoke_json() {
  local container="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  run_container_json "$container" "$stdout_file" "$stderr_file" \
    "${QA_CONTAINER_DRIVER_PW_ENV[@]+"${QA_CONTAINER_DRIVER_PW_ENV[@]}"}" \
    -e QA_CUSTOMER_JWT -e QA_SOCKET_ORIGIN -e SOCKET_BACKEND_ROOT -e QA_SOCKET_DRIVER_PHONE \
    -w /srv/tride/backend/socket-qa -- \
    node run-urgent-gate-false-smoke.mjs
}

# Copy QA driver password into container (never log password bytes).
qa_sync_driver_password_to_container() {
  local container="$1"
  local qa_dir="$2"
  if [ -z "${QA_DRIVER_PASSWORD:-}" ] && [ -z "${QA_DRIVER_PASSWORD_FILE:-}" ]; then
    if docker exec "$container" test -f /srv/tride/backend/.qa-driver-password 2>/dev/null; then
      urgent_docker_cp_required "$qa_dir" "$container" qa-driver-password.cjs /srv/tride/backend/qa-driver-password.cjs
      QA_CONTAINER_DRIVER_PW_ENV=( -e QA_DRIVER_PASSWORD_FILE=/srv/tride/backend/.qa-driver-password )
      return 0
    fi
    # shellcheck source=qa-bootstrap-driver-password.sh
    source "$qa_dir/qa-bootstrap-driver-password.sh"
  fi
  urgent_docker_cp_required "$qa_dir" "$container" qa-driver-password.cjs /srv/tride/backend/qa-driver-password.cjs
  if [ -n "${QA_DRIVER_PASSWORD:-}" ]; then
    QA_CONTAINER_DRIVER_PW_ENV=( -e "QA_DRIVER_PASSWORD=$QA_DRIVER_PASSWORD" )
  else
    docker cp "$QA_DRIVER_PASSWORD_FILE" "$container:/srv/tride/backend/.qa-driver-password"
    docker exec "$container" chmod 600 /srv/tride/backend/.qa-driver-password 2>/dev/null || true
    QA_CONTAINER_DRIVER_PW_ENV=( -e QA_DRIVER_PASSWORD_FILE=/srv/tride/backend/.qa-driver-password )
    if [ "${QA_DRIVER_PASSWORD_EPHEMERAL:-}" = "1" ]; then
      printf '%s\n' "$QA_DRIVER_PASSWORD_FILE" >"$qa_dir/.qa-ephemeral-password-file.path"
      chmod 600 "$qa_dir/.qa-ephemeral-password-file.path" 2>/dev/null || true
    fi
  fi
}

write_urgent_fail_artifact() {
  local fail_file="$1"
  local stage="$2"
  local node_exit="$3"
  local json_file="$4"
  local stderr_file="$5"
  {
    echo "stage=$stage"
    echo "nodeExit=$node_exit"
    echo "out=${OUT:-unknown}"
    echo "json=$json_file"
    echo "stderr=$stderr_file"
  } | tee "$fail_file"
  if [ -n "$stderr_file" ] && [ -s "$stderr_file" ]; then
    echo "--- stderr (first 30 lines) ---" >>"$fail_file"
    head -n 30 "$stderr_file" >>"$fail_file" || true
  fi
  if [ -n "$json_file" ] && [ -s "$json_file" ]; then
    echo "--- json (first 40 lines) ---" >>"$fail_file"
    head -n 40 "$json_file" >>"$fail_file" || true
  fi
}

# Always returns 0; sets ASSERT_JSON_IN_CONTAINER_EC.
assert_json_in_container() {
  local container="$1"
  local assert_script="$2"
  local json_path="$3"
  local log_file="$4"
  local cmd_ec=0

  ASSERT_JSON_IN_CONTAINER_EC=0

  docker cp "$assert_script" "$container:/srv/tride/backend/$(basename "$assert_script")"
  docker cp "$json_path" "$container:/tmp/urgent-assert-input.json"
  if docker exec -w /srv/tride/backend "$container" \
    node "/srv/tride/backend/$(basename "$assert_script")" /tmp/urgent-assert-input.json \
    >"$log_file" 2>"${log_file%.log}.stderr.log"; then
    cmd_ec=0
  else
    cmd_ec=$?
  fi
  ASSERT_JSON_IN_CONTAINER_EC=$cmd_ec
  return 0
}
