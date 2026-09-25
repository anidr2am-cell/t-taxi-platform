#!/bin/bash
# Alias for isolated internal-only API start (no host port publish).
exec "$(dirname "$0")/start-api-internal.sh" "$@"
