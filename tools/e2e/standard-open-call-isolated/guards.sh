#!/bin/bash
# Safety guards before STANDARD open-call QA. Run on tride-staging only.
set -eu

QA_NET="${QA_NET:-tride-qa-admin-net}"
QA_DB_HOST="${QA_DB_HOST:-tride-qa-admin-db}"
QA_DB_NAME="${QA_DB_NAME:-tride_qa_admin}"
FORBIDDEN_DB_HOSTS="tride-db db mysql"

echo "=== QA guard: network ==="
if ! docker network inspect "$QA_NET" >/dev/null 2>&1; then
  echo "FAIL: network $QA_NET missing"
  exit 1
fi

echo "=== QA guard: API container networks (socket/internal mode) ==="
for c in tride-qa-admin-api tride-qa-oc-true-api; do
  if docker inspect "$c" >/dev/null 2>&1; then
    nets="$(docker inspect "$c" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}')"
    ports="$(docker port "$c" 2>/dev/null || true)"
    echo "$c networks: $nets"
    if [ -n "$ports" ]; then
      echo "WARN: $c publishes host ports (expected internal-only for socket QA): $ports"
    fi
    if echo "$nets" | grep -qw bridge; then
      echo "WARN: $c attached to default bridge"
    fi
  fi
done

echo "=== QA guard: DB host name ==="
if echo "$QA_DB_HOST" | grep -qE 'tride-db|(^|/)tride_staging'; then
  echo "FAIL: DB_HOST looks like production ($QA_DB_HOST)"
  exit 1
fi
if [ "$QA_DB_NAME" = "tride_staging" ]; then
  echo "FAIL: DB_NAME is production tride_staging"
  exit 1
fi

echo "=== QA guard: API container mounts (must not bind prod uploads) ==="
for c in tride-qa-admin-api tride-qa-oc-false-api tride-qa-oc-true-api; do
  if docker inspect "$c" >/dev/null 2>&1; then
    binds=$(docker inspect "$c" --format '{{json .HostConfig.Binds}}')
    if echo "$binds" | grep -q '/opt/t-ride'; then
      echo "FAIL: $c has host bind under /opt/t-ride: $binds"
      exit 1
    fi
  fi
done

echo "=== QA guard: env keys (values redacted) ==="
for envfile in "$@"; do
  [ -f "$envfile" ] || continue
  for forbidden in FIREBASE FCM SMTP_PASSWORD GOOGLE_CLIENT KAKAO_CLIENT LINE_CLIENT; do
    if grep -q "^${forbidden}" "$envfile" 2>/dev/null; then
      echo "WARN: $envfile contains $forbidden* — ensure empty/disabled for QA"
    fi
  done
  grep -E '^(DB_HOST|DB_NAME|CONTACT_CONNECTION_REQUIRED|NODE_ENV)=' "$envfile" | sed 's/=.*/=***/'
done

echo "=== QA guard: no notification_devices in QA DB (FCM tokens) ==="
if docker ps --format '{{.Names}}' | grep -q "^${QA_DB_HOST}$"; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  . "${QA_ENV_FILE:-/opt/t-ride/releases/qa-admin-88ba7ba/qa.env}"
  set +a
  count=$(docker exec -i "$QA_DB_HOST" mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='notification_devices';" 2>/dev/null || echo 0)
  if [ "$count" = "1" ]; then
    nd=$(docker exec -i "$QA_DB_HOST" mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -e \
      "SELECT COUNT(*) FROM notification_devices;" 2>/dev/null || echo 0)
    echo "notification_devices rows: $nd (expect 0)"
    if [ "${nd:-0}" != "0" ]; then
      echo "FAIL: QA DB has device tokens"
      exit 1
    fi
  fi
fi

echo "GUARD OK"
