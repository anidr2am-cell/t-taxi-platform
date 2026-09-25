#!/usr/bin/env bash
# Fake docker: "exec" always fails with exit 1; "image inspect" succeeds.
if [[ "$1" == "image" && "$2" == "inspect" ]]; then
  exit 0
fi
if [[ "$1" == "exec" ]]; then
  exit 1
fi
echo "fake-docker-exec-fail: unsupported: $*" >&2
exit 127
