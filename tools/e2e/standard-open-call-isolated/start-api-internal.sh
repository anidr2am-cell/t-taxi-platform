#!/bin/bash
# Isolated QA API on internal network only (no host port publish, no default bridge).
# Usage: start-api-internal.sh false|true
set -eu

GATE="${1:-false}"
RELEASE_DIR="${RELEASE_DIR:-/opt/t-ride/releases/qa-admin-88ba7ba}"
QA_NET="${QA_NET:-tride-qa-admin-net}"
QA_DB_CONTAINER="${QA_DB_CONTAINER:-tride-qa-admin-db}"
BACKEND_IMAGE="${BACKEND_IMAGE:-tride-staging-tride-backend:latest}"

if [ "$GATE" = "true" ]; then
  API_NAME="tride-qa-oc-true-api"
  ENV_FILE="$RELEASE_DIR/qa-gate-true.env"
else
  API_NAME="tride-qa-admin-api"
  ENV_FILE="$RELEASE_DIR/qa.env"
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE"
  exit 1
fi

docker rm -f "$API_NAME" 2>/dev/null || true

docker run -d \
  --name "$API_NAME" \
  --network "$QA_NET" \
  --env-file "$ENV_FILE" \
  -e "DB_HOST=$QA_DB_CONTAINER" \
  "$BACKEND_IMAGE"

if docker port "$API_NAME" 3000/tcp 2>/dev/null | grep -q .; then
  echo "FAIL: unexpected host port publish on internal-only API"
  docker port "$API_NAME" || true
  docker rm -f "$API_NAME"
  exit 1
fi

nets="$(docker inspect "$API_NAME" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}')"
if ! echo "$nets" | grep -qw "$QA_NET"; then
  echo "FAIL: API not on $QA_NET (networks: $nets)"
  exit 1
fi
if echo "$nets" | grep -qw bridge; then
  echo "FAIL: API must not stay on default bridge (networks: $nets)"
  exit 1
fi

echo "Waiting for health on $API_NAME (internal) ..."
for i in $(seq 1 60); do
  if docker exec "$API_NAME" wget -qO- http://127.0.0.1:3000/api/v1/health 2>/dev/null | grep -q '"database":"connected"'; then
    echo "API healthy ($API_NAME, gate=$GATE, internal $QA_NET only)"
    exit 0
  fi
  sleep 2
done

echo "FAIL: API did not become healthy"
docker logs "$API_NAME" --tail 40
exit 1
