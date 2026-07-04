#!/usr/bin/env bash
# Apply numbered SQL migrations on Linux (Gabia VPS / staging).
# Reads DB_* from backend/.env by default (same behaviour as migrate.ps1).
#
# Usage:
#   ./migrate.sh
#   ./migrate.sh --env-file /srv/ttaxi/current/backend/.env
#   DB_HOST=127.0.0.1 DB_USER=root DB_PASSWORD=secret DB_NAME=ttaxi_staging ./migrate.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_DIR="$SCRIPT_DIR"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../backend/.env}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --database-dir)
      DATABASE_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

read_env() {
  local key="$1"
  local default="${2:-}"
  if [[ -f "$ENV_FILE" ]]; then
    local line
    line="$(grep -E "^${key}=" "$ENV_FILE" | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      local value="${line#*=}"
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      echo "$value"
      return
    fi
  fi
  echo "${!key:-$default}"
}

DB_HOST="$(read_env DB_HOST 127.0.0.1)"
DB_PORT="$(read_env DB_PORT 3306)"
DB_USER="$(read_env DB_USER root)"
DB_PASSWORD="$(read_env DB_PASSWORD "")"
DB_NAME="$(read_env DB_NAME ttaxi)"

if [[ ! "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Invalid database name: $DB_NAME" >&2
  exit 1
fi

if ! command -v mysql >/dev/null 2>&1; then
  echo "mysql client not found. Install mysql-client (e.g. apt install mysql-client)." >&2
  exit 1
fi

MYSQL_ARGS=(--host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" --default-character-set=utf8mb4)
if [[ -n "$DB_PASSWORD" ]]; then
  MYSQL_ARGS+=(--password="$DB_PASSWORD")
fi

convert_sql() {
  local sql="$1"
  sql="$(printf '%s' "$sql" | sed -E "s/^CREATE DATABASE IF NOT EXISTS \`?ttaxi\`?/CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`/Ig")"
  sql="$(printf '%s' "$sql" | sed -E "s/^USE \`?ttaxi\`?;/USE \`$DB_NAME\`;/Ig")"
  printf '%s' "$sql"
}

mapfile -t MIGRATION_FILES < <(find "$DATABASE_DIR" -maxdepth 1 -type f -name '*.sql' | sort)

if [[ ${#MIGRATION_FILES[@]} -eq 0 ]]; then
  echo "No SQL files found in $DATABASE_DIR" >&2
  exit 1
fi

echo "Using database '$DB_NAME' on ${DB_HOST}:${DB_PORT} as ${DB_USER}"
echo "Env file: ${ENV_FILE}"

for file in "${MIGRATION_FILES[@]}"; do
  base="$(basename "$file")"
  if [[ ! "$base" =~ ^[0-9]+_.+\.sql$ ]]; then
    continue
  fi
  echo "Running $base ..."
  sql="$(convert_sql "$(cat "$file")")"
  if ! printf '%s\n' "$sql" | mysql "${MYSQL_ARGS[@]}" --show-warnings 2>&1; then
    echo "$base failed" >&2
    exit 1
  fi
done

echo "Database migration completed."
