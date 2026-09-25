#!/bin/bash
# Remove host ephemeral QA driver password file (never log contents). Source only.
set -eu

qa_cleanup_ephemeral_driver_password() {
  if [ "${QA_DRIVER_PASSWORD_EPHEMERAL:-}" != "1" ]; then
    return 0
  fi
  if [ -z "${QA_DRIVER_PASSWORD_FILE:-}" ]; then
    return 0
  fi
  # KEEP_QA_RUNNING success: password file kept until stop-qa-ui.sh
  if [ "${KEEP_QA_RUNNING:-0}" = "1" ] && [ "${QA_UI_SUCCESS:-false}" = "true" ]; then
    return 0
  fi
  if [ "${KEEP_QA_RUNNING:-0}" = "1" ] && [ "${SUITE_FAIL:-0}" = "0" ]; then
    return 0
  fi
  rm -f "$QA_DRIVER_PASSWORD_FILE" 2>/dev/null || true
  if [ -n "${QA_EPHEMERAL_MARKER:-}" ]; then
    rm -f "$QA_EPHEMERAL_MARKER" 2>/dev/null || true
  fi
  unset QA_DRIVER_PASSWORD_FILE QA_DRIVER_PASSWORD_EPHEMERAL QA_EPHEMERAL_MARKER
}
