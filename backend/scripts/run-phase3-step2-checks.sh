#!/bin/bash
set -eu
source /opt/t-ride/deploy/docker/.env
SCRIPT="$1"
docker cp "/opt/t-ride/backend/scripts/${SCRIPT}" tride-db:/tmp/check.sql
docker exec tride-db sh -lc 'mysql -N -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /tmp/check.sql'
