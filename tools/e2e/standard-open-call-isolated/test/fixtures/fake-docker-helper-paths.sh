#!/usr/bin/env bash
# Simulates "docker run node helper-paths" using host node + parsed -v/-e (no real container).
set -eu

if [[ "$*" == *"image inspect"* ]]; then
  exit 0
fi

if [[ "${1:-}" != "run" ]]; then
  echo "fake-docker-helper-paths: unsupported: $*" >&2
  exit 127
fi

shift
host_root=""
smoke_tmp=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v)
      pair="$2"
      if [[ "$pair" == *:/verify/root:ro ]]; then
        host_root="${pair%%:/verify/root:ro}"
      fi
      if [[ "$pair" == *:/tmp/verify-writable:rw ]]; then
        smoke_tmp="${pair%%:/tmp/verify-writable:rw}"
      fi
      shift 2
      ;;
    -e)
      export "$2"
      shift 2
      ;;
    --entrypoint)
      shift 2
      ;;
    --pull=*)
      shift
      ;;
    --network)
      shift 2
      ;;
    --rm)
      shift
      ;;
    /*verify-urgent-qa-helper-paths.cjs)
      script_path="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$host_root" || -z "$smoke_tmp" ]]; then
  echo "fake-docker-helper-paths: missing mount" >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "fake-docker-helper-paths: host node required for simulation" >&2
  exit 127
fi

export VERIFY_ROOT="$host_root"
export VERIFY_SMOKE_TMP="$smoke_tmp"
exec node "$host_root/verify-urgent-qa-helper-paths.cjs"
