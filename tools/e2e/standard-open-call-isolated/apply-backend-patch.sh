#!/bin/bash
# Copy pickup-conflict sources from repo backend/src into a running QA API container.
set -eu

CONTAINER="${1:?container name}"
BACKEND_ROOT="${2:-${BACKEND_ROOT:-}}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$BACKEND_ROOT" ]; then
  if [ -d "$ROOT/../../../backend/src" ]; then
    BACKEND_ROOT="$(cd "$ROOT/../../../backend" && pwd)"
  else
    echo "FAIL: pass BACKEND_ROOT or run from repo with backend/src"
    exit 1
  fi
fi

for rel in \
  src/policies/driverBookingConflictPolicy.js \
  src/repositories/booking.repository.js \
  src/repositories/driver.repository.js \
  src/services/booking.service.js
do
  src="$BACKEND_ROOT/$rel"
  test -f "$src"
  docker cp "$src" "$CONTAINER:/srv/tride/backend/$rel"
done

echo "PATCH_APPLIED container=$CONTAINER backend_root=$BACKEND_ROOT"
