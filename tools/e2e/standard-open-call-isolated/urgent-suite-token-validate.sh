# shellcheck shell=bash
# Shared bearer token capture validation (source only — no secrets logged).

validate_bearer_token() {
  local label="$1"
  local tok="$2"

  if [ -z "$tok" ]; then
    echo "FAIL: empty $label token" >&2
    return 1
  fi

  if printf '%s' "$tok" | grep -q '{'; then
    echo "FAIL: $label token looks like JSON (capture contaminated)" >&2
    return 1
  fi

  case "$tok" in
    *$'\n'*|*$'\r'*)
      echo "FAIL: $label token must not contain CR or LF" >&2
      return 1
      ;;
  esac

  case "$tok" in
    *[[:space:]]*)
      echo "FAIL: $label token must not contain whitespace" >&2
      return 1
      ;;
  esac

  if [ "${#tok}" -lt 20 ]; then
    echo "FAIL: $label token too short" >&2
    return 1
  fi

  return 0
}
