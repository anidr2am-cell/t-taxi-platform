#!/usr/bin/env bash
# Apply fare-table image seed on T-Ride staging (DigitalOcean (Singapore)).
# Safe scope only: /opt/t-ride, tride-* containers. Never touches /opt/ktaxi or ktaxi-*.
#
# Usage (on DigitalOcean server as a user with docker access):
#   bash /opt/t-ride/deploy/scripts/apply-staging-fare-table.sh
set -euo pipefail

COMPOSE_FILE="/opt/t-ride/deploy/docker/docker-compose.staging.yml"
COMPOSE_DIR="/opt/t-ride/deploy/docker"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

cd /opt/t-ride
echo "==> git pull origin main"
git pull origin main

cd "$COMPOSE_DIR"
echo "==> rebuild tride-backend and tride-frontend"
docker compose -f docker-compose.staging.yml up -d --build tride-backend tride-frontend

echo "==> run database migrations (includes 28_fare_table_image_seed.sql)"
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/database && ./migrate.sh'

echo "==> staging fare table API smoke"
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/backend && STAGING_BASE_URL=http://127.0.0.1:3000 node scripts/staging-fare-table-smoke.js'

echo "Done. Verify UI at http://159.89.192.55:3101/ (KTaxi 80/443 untouched)."
