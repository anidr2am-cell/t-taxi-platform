#!/usr/bin/env bash
# Fake docker exec: record argv (redact QA_DRIVER_PASSWORD values), exit 0.
set -eu
argv_file="${FAKE_DOCKER_ARGV_FILE:-}"
if [ -z "$argv_file" ]; then
  echo "fake-docker-record-exec: set FAKE_DOCKER_ARGV_FILE" >&2
  exit 2
fi
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then
  exit 0
fi
if [ "${1:-}" = "exec" ]; then
  : >"$argv_file"
  for arg in "$@"; do
    case "$arg" in
      QA_DRIVER_PASSWORD=*)
        printf '%s\n' 'QA_DRIVER_PASSWORD=<redacted>' >>"$argv_file"
        ;;
      *)
        printf '%s\n' "$arg" >>"$argv_file"
        ;;
    esac
  done
  exit 0
fi
echo "fake-docker-record-exec: unsupported" >&2
exit 127
