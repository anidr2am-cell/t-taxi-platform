#!/bin/bash
# Reset disposable QA MariaDB (schema + catalog + QA trigger definers).
set -eu

RELEASE_DIR="${RELEASE_DIR:-/opt/t-ride/releases/qa-admin-88ba7ba}"
QA_DB_CONTAINER="${QA_DB_CONTAINER:-tride-qa-admin-db}"
QA_NET="${QA_NET:-tride-qa-admin-net}"
QA_ENV_FILE="${QA_ENV_FILE:-$RELEASE_DIR/qa.env}"

# shellcheck disable=SC1091
set -a
. "$QA_ENV_FILE"
set +a

echo "Starting $QA_DB_CONTAINER on $QA_NET ..."
docker start "$QA_DB_CONTAINER" 2>/dev/null || docker run -d \
  --name "$QA_DB_CONTAINER" \
  --network "$QA_NET" \
  -e MARIADB_DATABASE="$DB_NAME" \
  -e MARIADB_ROOT_PASSWORD="$DB_PASSWORD" \
  mariadb:10.11

for i in $(seq 1 30); do
  if docker exec "$QA_DB_CONTAINER" mysqladmin ping -uroot -p"$DB_PASSWORD" --silent 2>/dev/null; then
    break
  fi
  sleep 2
done

echo "Recreating database $DB_NAME ..."
docker exec -i "$QA_DB_CONTAINER" mysql -uroot -p"$DB_PASSWORD" -e \
  "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo "Importing schema + catalog + triggers ..."
docker exec -i "$QA_DB_CONTAINER" mysql -uroot -p"$DB_PASSWORD" "$DB_NAME" < "$RELEASE_DIR/schema.sql"
docker exec -i "$QA_DB_CONTAINER" mysql -uroot -p"$DB_PASSWORD" "$DB_NAME" < "$RELEASE_DIR/catalog.sql"
if [ -f "$RELEASE_DIR/triggers-qa.sql" ]; then
  docker exec -i "$QA_DB_CONTAINER" mysql -uroot -p"$DB_PASSWORD" "$DB_NAME" < "$RELEASE_DIR/triggers-qa.sql"
else
  docker exec -i "$QA_DB_CONTAINER" mysql -uroot -p"$DB_PASSWORD" "$DB_NAME" < "$RELEASE_DIR/triggers.sql"
fi

echo "DB reset complete."
