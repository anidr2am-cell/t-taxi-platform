#!/bin/bash
set -eu
source /opt/t-ride/deploy/docker/.env

SCENARIO="${1:?scenario required (receipt|manual)}"
BOOKING="${2:?booking number required}"

SQL_FILE="/tmp/settlement-approval-replay-check-${SCENARIO}-${BOOKING}.sql"
sed "s/@BOOKING_NUMBER@/${BOOKING}/g" \
  /opt/t-ride/backend/scripts/staging-settlement-approval-replay-db-check.sql > "${SQL_FILE}"
docker cp "${SQL_FILE}" tride-db:/tmp/settlement-approval-replay-check.sql
OUTPUT="$(docker exec tride-db sh -lc 'mysql -N -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /tmp/settlement-approval-replay-check.sql')"
IFS=$'\t' read -r STATUS COMMISSION_STATUS COMMISSION_PAID_AT_SET COMMISSION_APPROVED_COUNT MANUAL_APPROVED_COUNT SETTLEMENT_APPROVED_OUTBOX_COUNT ACTIVE_ASSIGNMENT_COUNT ACTIVE_RECEIPT_FILES <<< "${OUTPUT}"

echo "DB_CHECK scenario=${SCENARIO} booking=${BOOKING}"
echo "DB_STATUS=${STATUS}"
echo "DB_COMMISSION_STATUS=${COMMISSION_STATUS}"
echo "DB_COMMISSION_PAID_AT_SET=${COMMISSION_PAID_AT_SET}"
echo "DB_COMMISSION_APPROVED_COUNT=${COMMISSION_APPROVED_COUNT}"
echo "DB_MANUAL_APPROVED_COUNT=${MANUAL_APPROVED_COUNT}"
echo "DB_SETTLEMENT_APPROVED_OUTBOX_COUNT=${SETTLEMENT_APPROVED_OUTBOX_COUNT}"
echo "DB_ACTIVE_ASSIGNMENT_COUNT=${ACTIVE_ASSIGNMENT_COUNT}"
echo "DB_ACTIVE_RECEIPT_FILES=${ACTIVE_RECEIPT_FILES}"

fail=0
assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "${actual}" != "${expected}" ]; then
    echo "DB_ASSERT_FAIL ${label} expected=${expected} actual=${actual}"
    fail=1
  fi
}

assert_eq status COMPLETED "${STATUS}"
assert_eq commission_status PAID "${COMMISSION_STATUS}"
assert_eq commission_paid_at_set 1 "${COMMISSION_PAID_AT_SET}"
assert_eq settlement_approved_outbox_count 1 "${SETTLEMENT_APPROVED_OUTBOX_COUNT}"
assert_eq active_assignment_count 0 "${ACTIVE_ASSIGNMENT_COUNT}"

if [ "${SCENARIO}" = "receipt" ]; then
  assert_eq commission_approved_count 1 "${COMMISSION_APPROVED_COUNT}"
  assert_eq manual_approved_count 0 "${MANUAL_APPROVED_COUNT}"
  assert_eq active_receipt_files 1 "${ACTIVE_RECEIPT_FILES}"
elif [ "${SCENARIO}" = "manual" ]; then
  assert_eq commission_approved_count 0 "${COMMISSION_APPROVED_COUNT}"
  assert_eq manual_approved_count 1 "${MANUAL_APPROVED_COUNT}"
  assert_eq active_receipt_files 0 "${ACTIVE_RECEIPT_FILES}"
else
  echo "DB_ASSERT_FAIL unknown_scenario=${SCENARIO}"
  exit 1
fi

if [ "${fail}" -ne 0 ]; then
  exit 1
fi

echo "DB_CHECK_PASS scenario=${SCENARIO} booking=${BOOKING}"
