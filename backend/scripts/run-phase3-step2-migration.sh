#!/bin/bash
set -eu
source /opt/t-ride/deploy/docker/.env
docker cp /tmp/51_settlement_receipt_idempotency.sql tride-db:/tmp/51_settlement_receipt_idempotency.sql
docker exec tride-db sh -lc 'mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /tmp/51_settlement_receipt_idempotency.sql'
