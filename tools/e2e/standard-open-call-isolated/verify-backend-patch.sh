#!/bin/bash
# Compare container backend files with local backend/src (SHA256). No secret output.
set -eu

CONTAINER="${1:?container}"
BACKEND_ROOT="${BACKEND_ROOT:-}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$BACKEND_ROOT" ]; then
  if [ -d "$ROOT/../../../backend/src" ]; then
    BACKEND_ROOT="$(cd "$ROOT/../../../backend" && pwd)"
  else
    echo "FAIL: set BACKEND_ROOT to repo backend/ (contains src/)"
    exit 1
  fi
fi

FILES=(
  src/policies/driverBookingConflictPolicy.js
  src/repositories/booking.repository.js
  src/repositories/driver.repository.js
  src/services/booking.service.js
)

echo "BACKEND_ROOT=$BACKEND_ROOT"
echo "CONTAINER=$CONTAINER"
git -C "$BACKEND_ROOT/.." rev-parse HEAD 2>/dev/null | sed 's/^/local_git_head=/' || echo "local_git_head=unknown"

mismatch=0
for rel in "${FILES[@]}"; do
  local="$BACKEND_ROOT/$rel"
  if [ ! -f "$local" ]; then
    echo "MISSING_LOCAL $rel"
    mismatch=$((mismatch + 1))
    continue
  fi
  lsha="$(sha256sum "$local" | awk '{print $1}')"
  rsha="$(docker exec "$CONTAINER" sha256sum "/srv/tride/backend/$rel" 2>/dev/null | awk '{print $1}' || echo missing)"
  if [ "$lsha" = "$rsha" ]; then
    echo "MATCH $rel sha256=$lsha"
  else
    echo "DIFF $rel local=$lsha container=$rsha"
    mismatch=$((mismatch + 1))
  fi
done

if [ "$mismatch" -ne 0 ]; then
  echo "PATCH_VERIFY_FAIL mismatches=$mismatch"
  exit 1
fi
echo "PATCH_VERIFY_OK"
