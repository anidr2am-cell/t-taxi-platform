#!/bin/bash
set -eu
BOOKING="${1:?booking number required}"
source /opt/t-ride/deploy/docker/.env
SQL_FILE="/tmp/urgent-timeout-hardening-check-${BOOKING}.sql"
sed "s/@BOOKING_NUMBER@/${BOOKING}/g" /opt/t-ride/backend/scripts/staging-urgent-timeout-hardening-db-check.sql > "${SQL_FILE}"
docker cp "${SQL_FILE}" tride-db:/tmp/urgent-timeout-hardening-check.sql
docker exec tride-db sh -lc 'mysql -N -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /tmp/urgent-timeout-hardening-check.sql'
