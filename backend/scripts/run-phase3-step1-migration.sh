#!/bin/bash
set -eu
source /opt/t-ride/deploy/docker/.env
docker cp /tmp/50_booking_contact_connection_active_guard.sql tride-db:/tmp/50_booking_contact_connection_active_guard.sql
docker exec tride-db sh -lc 'mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /tmp/50_booking_contact_connection_active_guard.sql'
