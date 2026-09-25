#!/usr/bin/env bash
# Test double for verify-urgent-suite Docker assert path (no real containers).
# FAKE_DOCKER_EXIT controls exit code for "docker run" invocations.
if [[ "$*" == *"image inspect"* ]]; then
  exit 0
fi
if [[ "$1" == "run" ]]; then
  exit "${FAKE_DOCKER_EXIT:-0}"
fi
echo "fake-docker-for-verify: unsupported args: $*" >&2
exit 127
