#!/bin/bash
set -eu
cd /opt/t-ride
source /opt/t-ride/deploy/docker/.env

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
docker cp /opt/t-ride/backend/scripts/staging-settlement-approval-replay-e2e.js \
  tride-backend:/srv/tride/backend/scripts/staging-settlement-approval-replay-e2e.js
docker cp /opt/t-ride/backend/scripts/staging-receipt-idempotency-e2e.js \
  tride-backend:/srv/tride/backend/scripts/staging-receipt-idempotency-e2e.js
docker cp /opt/t-ride/backend/scripts/e2eRegressionCleanup.js \
  tride-backend:/srv/tride/backend/scripts/e2eRegressionCleanup.js
docker cp /opt/t-ride/backend/scripts/staging-booking-regression.js \
  tride-backend:/srv/tride/backend/scripts/staging-booking-regression.js

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
  tride-backend node scripts/staging-settlement-approval-replay-e2e.js \
  | tee /tmp/settlement-approval-replay-e2e.log

RECEIPT_BOOKING="$(grep -E '"RECEIPT_BOOKING"' /tmp/settlement-approval-replay-e2e.log | tail -n 1 | sed -E 's/.*"RECEIPT_BOOKING": "([^"]+)".*/\1/')"
MANUAL_BOOKING="$(grep -E '"MANUAL_BOOKING"' /tmp/settlement-approval-replay-e2e.log | tail -n 1 | sed -E 's/.*"MANUAL_BOOKING": "([^"]+)".*/\1/')"

if [ -n "${RECEIPT_BOOKING}" ]; then
  bash /opt/t-ride/backend/scripts/run-staging-settlement-approval-replay-db-check.sh receipt "${RECEIPT_BOOKING}"
fi

if [ -n "${MANUAL_BOOKING}" ]; then
  bash /opt/t-ride/backend/scripts/run-staging-settlement-approval-replay-db-check.sh manual "${MANUAL_BOOKING}"
fi
