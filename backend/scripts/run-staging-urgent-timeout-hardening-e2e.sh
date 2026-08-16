#!/bin/bash
set -eu
source /opt/t-ride/deploy/docker/.env

cleanup() {
  local rc=$?
  docker exec tride-backend rm -f /srv/tride/.env.e2e.local >/dev/null 2>&1 || true
  exit "$rc"
}

trap cleanup EXIT

read_env() {
  local key="$1"
  local file="/opt/t-ride/.env.e2e.local"
  local line
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  line="${line#${key}=}"
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"
  printf '%s' "$line"
}

TRIDE_TEST_ADMIN_EMAIL="$(read_env TRIDE_TEST_ADMIN_EMAIL)"
TRIDE_TEST_ADMIN_PASSWORD="$(read_env TRIDE_TEST_ADMIN_PASSWORD)"
TRIDE_TEST_DRIVER_EMAIL="$(read_env TRIDE_TEST_DRIVER_EMAIL)"
TRIDE_TEST_DRIVER_PASSWORD="$(read_env TRIDE_TEST_DRIVER_PASSWORD)"

docker cp /opt/t-ride/.env.e2e.local tride-backend:/srv/tride/.env.e2e.local
docker cp /opt/t-ride/backend/scripts/staging-urgent-timeout-hardening-e2e.js tride-backend:/srv/tride/backend/scripts/staging-urgent-timeout-hardening-e2e.js

docker exec \
  -e TRIDE_PROVISION_TEST_ACCOUNTS=1 \
  -e TRIDE_RESET_TEST_ACCOUNT_PASSWORDS=1 \
  -e DB_HOST=tride-db \
  -e DB_NAME="${DB_NAME:-tride_staging}" \
  -e DB_USER="${DB_USER:-tride_app}" \
  -e DB_PASSWORD="${DB_PASSWORD}" \
  -e TRIDE_TEST_ADMIN_EMAIL="${TRIDE_TEST_ADMIN_EMAIL}" \
  -e TRIDE_TEST_ADMIN_PASSWORD="${TRIDE_TEST_ADMIN_PASSWORD}" \
  -e TRIDE_TEST_DRIVER_EMAIL="${TRIDE_TEST_DRIVER_EMAIL}" \
  -e TRIDE_TEST_DRIVER_PASSWORD="${TRIDE_TEST_DRIVER_PASSWORD}" \
  tride-backend node scripts/provision-staging-test-accounts.js

docker exec \
  -e TRIDE_BASE_URL=https://trider.taxi \
  -e TRIDE_ADMIN_EMAIL="${TRIDE_TEST_ADMIN_EMAIL}" \
  -e TRIDE_ADMIN_PASSWORD="${TRIDE_TEST_ADMIN_PASSWORD}" \
  -e TRIDE_TEST_DRIVER_EMAIL="${TRIDE_TEST_DRIVER_EMAIL}" \
  -e TRIDE_TEST_DRIVER_PASSWORD="${TRIDE_TEST_DRIVER_PASSWORD}" \
  -e TRIDE_ALLOW_LIVE_BOOKING_REGRESSION=1 \
  tride-backend node scripts/staging-urgent-timeout-hardening-e2e.js | tee /tmp/urgent-timeout-hardening-e2e.log

for BOOKING in $(grep -oE 'TX[0-9]{12}' /tmp/urgent-timeout-hardening-e2e.log | sort -u); do
  echo "DB_CHECK booking=${BOOKING}"
  bash /opt/t-ride/backend/scripts/run-staging-urgent-timeout-hardening-db-check.sh "${BOOKING}"
done
