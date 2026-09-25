# shellcheck shell=bash
# Shared helpers for driver UI QA scripts (source only).

QA_UI_SUCCESS=false
QA_NET="${QA_NET:-tride-qa-admin-net}"

qa_ui_fail() {
  echo "FAIL: $*" >&2
  exit 1
}

qa_ui_require_tools() {
  local root="$1"
  local br="$2"
  for rel in apply-backend-patch.sh verify-backend-patch.sh reset-db.sh start-api-internal.sh start-api.sh qa-driver-password.cjs; do
    if [ ! -f "$root/$rel" ]; then
      qa_ui_fail "missing required script $root/$rel"
    fi
  done
  for rel in \
    src/policies/driverBookingConflictPolicy.js \
    src/repositories/booking.repository.js \
    src/repositories/driver.repository.js \
    src/services/booking.service.js
  do
    if [ ! -f "$br/$rel" ]; then
      qa_ui_fail "missing patch source $br/$rel"
    fi
  done
  for rel in qa-ui-driver-auth.cjs run-ui-fixture.cjs run-ui-api-verify.cjs; do
    if [ ! -f "$root/$rel" ]; then
      qa_ui_fail "missing required file $root/$rel"
    fi
  done
}

qa_ui_container_ip() {
  local container="$1"
  local ip
  ip="$(docker inspect "$container" --format "{{(index .NetworkSettings.Networks \"$QA_NET\").IPAddress}}" 2>/dev/null || true)"
  if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
    qa_ui_fail "no IP on $QA_NET for container $container"
  fi
  echo "$ip"
}

qa_ui_wait_health_internal() {
  local container="$1"
  local attempts="${HEALTH_ATTEMPTS:-30}"
  local sleep_sec="${HEALTH_SLEEP_SEC:-2}"
  local ip i
  ip="$(qa_ui_container_ip "$container")"
  for i in $(seq 1 "$attempts"); do
    if docker exec "$container" wget -qO- http://127.0.0.1:3000/api/v1/health 2>/dev/null | grep -q '"database":"connected"'; then
      if curl -sf "http://${ip}:3000/api/v1/health" 2>/dev/null | grep -q '"database":"connected"'; then
        echo "health_ok container=$container qa_net_ip=$ip attempt=$i"
        return 0
      fi
    fi
    sleep "$sleep_sec"
  done
  qa_ui_fail "health timeout after ${attempts} attempts (container exec + http://${ip}:3000/api/v1/health)"
}

qa_ui_assert_port_and_network() {
  local container="$1"
  local port_line nets count net_internal ip

  if ! docker network inspect "$QA_NET" >/dev/null 2>&1; then
    qa_ui_fail "network $QA_NET missing"
  fi
  net_internal="$(docker network inspect "$QA_NET" --format '{{.Internal}}')"
  if [ "$net_internal" != "true" ]; then
    qa_ui_fail "$QA_NET must be Internal=true (got $net_internal)"
  fi

  port_line="$(docker port "$container" 3000/tcp 2>/dev/null || true)"
  if echo "$port_line" | grep -q .; then
    echo "port map: $port_line" >&2
    qa_ui_fail "QA API must not publish host ports (got: $port_line)"
  fi

  nets="$(docker inspect "$container" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}')"
  if echo "$nets" | grep -qw bridge; then
    qa_ui_fail "container must not be on default bridge (networks: $nets)"
  fi
  if ! echo "$nets" | grep -qw "$QA_NET"; then
    qa_ui_fail "container must be on $QA_NET (networks: $nets)"
  fi
  count="$(echo "$nets" | tr ' ' '\n' | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$count" != "1" ]; then
    qa_ui_fail "expected exactly one Docker network ($count): $nets"
  fi

  ip="$(qa_ui_container_ip "$container")"
  if ! curl -sf "http://${ip}:3000/api/v1/health" 2>/dev/null | grep -q '"database":"connected"'; then
    qa_ui_fail "host curl http://${ip}:3000/api/v1/health did not report database connected"
  fi

  echo "port_network_ok container=$container host_publish=none nets=$nets network_count=$count qa_net_ip=$ip Internal=true"
}

qa_ui_apply_patch_and_verify() {
  local container="$1"
  local br="$2"
  local root="$3"
  ( cd "$root" && ./apply-backend-patch.sh "$container" "$br" )
  docker restart "$container" >/dev/null
  qa_ui_wait_health_internal "$container"
  ( cd "$root" && BACKEND_ROOT="$br" ./verify-backend-patch.sh "$container" "$br" )
}

qa_ui_sync_driver_password() {
  local container="$1"
  local root="$2"
  if [ -z "${QA_DRIVER_PASSWORD:-}" ] && [ -z "${QA_DRIVER_PASSWORD_FILE:-}" ]; then
    if docker exec "$container" test -f /srv/tride/backend/.qa-driver-password 2>/dev/null; then
      QA_CONTAINER_DRIVER_PW_ENV=( -e QA_DRIVER_PASSWORD_FILE=/srv/tride/backend/.qa-driver-password )
      docker cp "$root/qa-driver-password.cjs" "$container:/srv/tride/backend/qa-driver-password.cjs"
      return 0
    fi
    # shellcheck source=qa-bootstrap-driver-password.sh
    source "$root/qa-bootstrap-driver-password.sh"
  fi
  docker cp "$root/qa-driver-password.cjs" "$container:/srv/tride/backend/qa-driver-password.cjs"
  if [ -n "${QA_DRIVER_PASSWORD:-}" ]; then
    QA_CONTAINER_DRIVER_PW_ENV=( -e "QA_DRIVER_PASSWORD=$QA_DRIVER_PASSWORD" )
  else
    docker cp "$QA_DRIVER_PASSWORD_FILE" "$container:/srv/tride/backend/.qa-driver-password"
    docker exec "$container" chmod 600 /srv/tride/backend/.qa-driver-password 2>/dev/null || true
    QA_CONTAINER_DRIVER_PW_ENV=( -e QA_DRIVER_PASSWORD_FILE=/srv/tride/backend/.qa-driver-password )
    if [ "${QA_DRIVER_PASSWORD_EPHEMERAL:-}" = "1" ]; then
      printf '%s\n' "$QA_DRIVER_PASSWORD_FILE" >"$root/.qa-ephemeral-password-file.path"
      chmod 600 "$root/.qa-ephemeral-password-file.path" 2>/dev/null || true
    fi
  fi
}

qa_ui_print_login_hint() {
  echo "--- QA driver login (no secrets below) ---"
  echo "Phone: ui-manifest.json -> driverLoginPhone (UI fixture uses driver user 10)."
  echo "Password: set QA_DRIVER_PASSWORD or QA_DRIVER_PASSWORD_FILE before run; or use ephemeral file from KEEP_QA_RUNNING output (server session only)."
  echo "Email (if prompted): qa-oc-driver-clean@example.invalid (virtual — see qa-fixture-accounts.md)"
}

qa_ui_print_keep_instructions() {
  local out_dir="$1"
  local gate_label="$2"
  local container="${3:-tride-qa-admin-api}"
  local ip
  ip="$(qa_ui_container_ip "$container")"
  echo ""
  echo "======== KEEP_QA_RUNNING=1 (success) ========"
  echo "QA API left up for manual Flutter UI ($gate_label)."
  echo "Manifest/API artifacts: $out_dir"
  echo "Server health:  curl -sS http://${ip}:3000/api/v1/health"
  echo "PC tunnel (Windows):"
  echo "  ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:13001:${ip}:3000 tride-staging"
  echo "Flutter defines: API_BASE_URL and SOCKET_URL = http://127.0.0.1:13001"
  echo "Login route:    http://127.0.0.1:8088/driver/login"
  qa_ui_print_login_hint
  if [ -n "${QA_DRIVER_PASSWORD_FILE:-}" ] && [ -z "${QA_DRIVER_PASSWORD:-}" ]; then
    echo "Ephemeral password file (read on server only, do not log contents): $QA_DRIVER_PASSWORD_FILE"
  fi
  echo "When finished, run teardown:"
  echo "  bash ${ROOT:-/opt/t-ride/releases/qa-standard-open-call}/stop-qa-ui.sh"
  echo "============================================="
}

qa_ui_cleanup() {
  local root="${ROOT:-}"
  if [ -n "$root" ] && [ -f "$root/qa-cleanup-ephemeral-driver-password.sh" ]; then
    # shellcheck source=qa-cleanup-ephemeral-driver-password.sh
    source "$root/qa-cleanup-ephemeral-driver-password.sh"
    qa_cleanup_ephemeral_driver_password
  fi
  docker rm -f tride-qa-admin-api tride-qa-oc-true-api 2>/dev/null || true
  docker stop tride-qa-admin-db 2>/dev/null || true
}

qa_ui_on_exit() {
  local ec=$?
  if [ "$QA_UI_SUCCESS" = true ] && [ "${KEEP_QA_RUNNING:-0}" = "1" ]; then
    exit "$ec"
  fi
  qa_ui_cleanup
  exit "$ec"
}
