#!/bin/bash
set -eu
source /opt/t-ride/deploy/docker/.env
BOOKING="${1:?booking number required}"
SQL_FILE="/tmp/receipt-idempotency-check-${BOOKING}.sql"
sed "s/@BOOKING_NUMBER@/${BOOKING}/g" /opt/t-ride/backend/scripts/staging-receipt-idempotency-db-check.sql > "${SQL_FILE}"
docker cp "${SQL_FILE}" tride-db:/tmp/receipt-idempotency-check.sql
docker exec tride-db sh -lc 'mysql -N -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /tmp/receipt-idempotency-check.sql'
