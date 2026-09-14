#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--port <port>] [--data clean|seed|persist]
  $0 [PORT]

Arguments:
  --port PORT   AFFiNE web port (default: 13010)
  --data MODE   clean (default): empty every booth
                seed: restore ~/.affine (home-seed), do not dump back
                persist: dump/restore ~/.affine (.booth/cache bind)

Examples:
  $0
  $0 --port 3010 --data persist

Prerequisites:
- AFFiNE must be pre-installed at /opt/affine
  (typically via COPY --from=ghcr.io/toeverything/affine:<tag> /app /opt/affine)
- Node.js 22, PostgreSQL, and Redis at runtime (the template requires them)

Notes:
- Creates start-affine-server / stop-affine-server
- The server is NOT started during build; add the autostart extension
- persist requires +persist (cache-dirs bind). seed requires +seed (home-seed).
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- defaults / args ----
AFFINE_SERVER_PORT="13010"
DATA_MODE="clean"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) shift; AFFINE_SERVER_PORT="${1:-13010}"; shift ;;
    --data) shift; DATA_MODE="${1:-clean}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        AFFINE_SERVER_PORT="$1"; shift
      else
        echo "❌ Unknown arg: $1" >&2; usage; exit 2
      fi
      ;;
  esac
done
DATA_MODE="$(echo "$DATA_MODE" | tr '[:upper:]' '[:lower:]')"
case "$DATA_MODE" in
  clean|seed|persist) ;;
  *)
    echo "⚠️  Unknown --data ${DATA_MODE}; using clean." >&2
    DATA_MODE="clean"
    ;;
esac

AFFINE_DIR="/opt/affine"
PROFILE_FILE="/etc/profile.d/70-cb-affine-server--profile.sh"
STARTER_FILE="/usr/local/bin/start-affine-server"
STOPPER_FILE="/usr/local/bin/stop-affine-server"
LIB_FILE="/usr/local/lib/cb-affine-data.sh"

# ---- verify AFFiNE is present ----
if [[ ! -f "$AFFINE_DIR/dist/main.js" ]]; then
  echo "❌ AFFiNE Server not found at $AFFINE_DIR"
  echo "   Use COPY --from=ghcr.io/toeverything/affine:<tag> /app /opt/affine"
  exit 1
fi

# ---- Node.js 22 (native addons in the official image are built for it) ----
need_node=1
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -v | sed 's/^v//' | cut -d. -f1)"
  # Official image native addons are built for Node 22. Catalog nodejs now
  # defaults to 24 (current LTS); a different major is an ABI mismatch.
  if [[ "${NODE_MAJOR:-0}" -eq 22 ]]; then
    echo "• Node.js already installed: $(node --version)"
    need_node=0
  else
    echo "• Node.js $(node --version) is not 22 (Affine native addons need 22)"
  fi
fi
if [[ "$need_node" -eq 1 ]]; then
  SETUPS_DIR="/opt/codingbooth/setups"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$SETUPS_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js 22 ..."
    "$SETUPS_DIR/nodejs--setup.sh" 22
  elif [[ -x "$SCRIPT_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js 22 ..."
    "$SCRIPT_DIR/nodejs--setup.sh" 22
  else
    echo "❌ nodejs--setup.sh not found (need Node.js 22)"
    exit 1
  fi
fi

# ---- runtime libraries (Prisma / official image) ----
export DEBIAN_FRONTEND=noninteractive
echo "• Installing OpenSSL (Prisma) ..."
apt-get update
apt-get install -y --no-install-recommends openssl ca-certificates

# pgvector: official compose uses pgvector/pgvector. Indexer is off by default,
# but CREATE EXTENSION vector still succeeds when the package is present.
if command -v pg_config >/dev/null 2>&1; then
  PG_VER="$(pg_config --version | grep -oE '[0-9]+' | head -1 || true)"
  if [[ -n "$PG_VER" ]]; then
    echo "• Installing postgresql-${PG_VER}-pgvector ..."
    apt-get install -y --no-install-recommends "postgresql-${PG_VER}-pgvector" || \
      echo "⚠️  postgresql-${PG_VER}-pgvector is not in this distro — continuing without it."
  fi
else
  echo "⚠️  PostgreSQL not installed yet; pgvector skipped (select postgresql)."
fi
rm -rf /var/lib/apt/lists/*

# World-writable, not just coder-owned: coder's UID is remapped to the host
# user's UID/GID at container start (see booth-entry), but that remap only
# re-chowns $HOME — anything outside it, like this directory, keeps whatever
# owner it had at build time regardless of who "coder" resolves to later.
# AFFiNE's GraphQL module writes a generated schema under $AFFINE_DIR/src on
# every boot (not just once), so a stale owner there is a hard crash (EACCES)
# rather than a cosmetic warning. Making it writable by anyone sidesteps the
# ownership question entirely instead of trying to guess or track the UID.
chmod -R a+rwX "$AFFINE_DIR"
if id coder >/dev/null 2>&1; then
  chown -R coder:coder "$AFFINE_DIR" || true
fi

mkdir -p /usr/local/lib
export BAKED_PORT="$AFFINE_SERVER_PORT"
export BAKED_DATA="$DATA_MODE"
envsubst '$BAKED_PORT $BAKED_DATA' <<'EOF' > "$LIB_FILE"
# shellcheck shell=bash
# Sourced by start-affine-server / stop-affine-server.

cb_affine_init() {
  PORT="${1:-${AFFINE_SERVER_PORT:-$BAKED_PORT}}"
  AFFINE_DIR="/opt/affine"
  DATA_DIR="${AFFINE_DATA_DIR:-$HOME/.affine}"
  DUMP_FILE="${DATA_DIR}/dumps/affine.dump"
  MODE="$(echo "${AFFINE_SERVER_DATA:-$BAKED_DATA}" | tr '[:upper:]' '[:lower:]')"
  case "$MODE" in
    clean|seed|persist) ;;
    *) MODE="clean" ;;
  esac
  export NODE_ENV="${NODE_ENV:-production}"
  export DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-selfhosted}"
  export AFFINE_INDEXER_ENABLED="${AFFINE_INDEXER_ENABLED:-false}"
  export PORT
  export AFFINE_SERVER_PORT="$PORT"
  export REDIS_SERVER_HOST="${REDIS_SERVER_HOST:-127.0.0.1}"
  export REDIS_SERVER_PORT="${REDIS_SERVER_PORT:-6379}"
  export PATH="/opt/affine/node_modules/.bin:${PATH}"
  CUSER="${USER:-coder}"
  export DATABASE_URL="${DATABASE_URL:-postgresql://${CUSER}@127.0.0.1:5432/affine}"
}

cb_affine_data_is_bind() {
  local p="$DATA_DIR"
  [[ -e "$p" ]] || return 1
  awk -v p="$p" '$5 == p { found=1 } END { exit !found }' /proc/self/mountinfo 2>/dev/null
}

cb_affine_resolve_mode() {
  if [[ "$MODE" == persist ]] && ! cb_affine_data_is_bind; then
    echo "⚠️  AFFINE_SERVER_DATA=persist but ${DATA_DIR} is not a cache bind." >&2
    echo "    Select affine-server+persist so cache-dirs mounts it. Using clean." >&2
    MODE="clean"
  fi
}

cb_affine_has_dump() {
  [[ -s "$DUMP_FILE" ]]
}

cb_affine_ensure_db() {
  createdb affine 2>/dev/null || true
  psql -d affine -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || \
    echo "⚠️  pgvector extension not available — indexer stays disabled."
}

cb_affine_wipe_db() {
  dropdb --if-exists affine >/dev/null 2>&1 || true
  createdb affine 2>/dev/null || true
  psql -d affine -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || true
}

cb_affine_wipe_files() {
  rm -rf "${DATA_DIR}/config" "${DATA_DIR}/storage" "${DATA_DIR}/dumps"
}

cb_affine_dump() {
  mkdir -p "${DATA_DIR}/dumps"
  if ! command -v pg_dump >/dev/null 2>&1; then
    echo "⚠️  pg_dump not available; skip persist dump." >&2
    return 0
  fi
  if psql -d affine -c 'SELECT 1' >/dev/null 2>&1; then
    echo "Dumping AFFiNE database to ${DUMP_FILE} ..."
    pg_dump -Fc affine > "$DUMP_FILE"
  fi
}

cb_affine_restore() {
  [[ -s "$DUMP_FILE" ]] || return 1
  echo "Restoring AFFiNE database from ${DUMP_FILE} ..."
  cb_affine_wipe_db
  pg_restore -d affine --no-owner --role="${USER:-coder}" "$DUMP_FILE" >/dev/null 2>&1 || \
    pg_restore -d affine "$DUMP_FILE" >/dev/null 2>&1 || true
}

cb_affine_wait_deps() {
  if command -v redis-server >/dev/null 2>&1 && ! redis-cli ping >/dev/null 2>&1; then
    mkdir -p "${HOME}/.redis/data" "${HOME}/.redis/log"
    echo "• Starting Redis ..."
    redis-server --dir "${HOME}/.redis/data" --daemonize yes \
      --logfile "${HOME}/.redis/log/redis.log"
  fi
  echo "• Waiting for PostgreSQL and Redis ..."
  local i pg_ok rd_ok
  for i in $(seq 1 60); do
    pg_ok=0; rd_ok=0
    if command -v pg_isready >/dev/null 2>&1 && pg_isready -q; then pg_ok=1; fi
    if command -v redis-cli >/dev/null 2>&1 && redis-cli ping >/dev/null 2>&1; then rd_ok=1; fi
    if [[ "$pg_ok" -eq 1 && "$rd_ok" -eq 1 ]]; then return 0; fi
    sleep 1
  done
  echo "❌ PostgreSQL and Redis must be running." >&2
  pg_isready || true
  redis-cli ping || true
  return 1
}

cb_affine_prepare_files() {
  mkdir -p "${DATA_DIR}/config" "${DATA_DIR}/storage"
  local cfg="${DATA_DIR}/config/config.json"
  if [[ ! -f "$cfg" ]]; then
    cat > "$cfg" <<JSON
{
  "server": {
    "name": "AFFiNE (CodingBooth)",
    "externalUrl": "http://localhost:${PORT}"
  },
  "copilot": {
    "enabled": true,
    "byok": {
      "enabled": true
    }
  }
}
JSON
  fi
  if [[ ! -f "${DATA_DIR}/config/private.key" ]]; then
    openssl ecparam -name prime256v1 -genkey -noout \
      -out "${DATA_DIR}/config/private.key"
  fi
}

cb_affine_migrate() {
  echo "• Running AFFiNE predeploy (migrations) ..."
  cd "$AFFINE_DIR"
  prisma migrate deploy
  SERVER_FLAVOR=script node ./dist/main.js run
}

cb_affine_stop_server() {
  local pid
  pid="$(pgrep -f '/opt/affine/dist/main.js' || true)"
  if [[ -n "$pid" ]]; then
    kill $pid 2>/dev/null || true
    sleep 1
    kill -9 $pid 2>/dev/null || true
  fi
}
EOF
chmod 644 "$LIB_FILE"

cat > "${PROFILE_FILE}" <<PROFILE
# AFFiNE Server environment
export AFFINE_SERVER_HOME="${AFFINE_DIR}"
export AFFINE_SERVER_PORT="${AFFINE_SERVER_PORT}"
export AFFINE_SERVER_URL="http://localhost:${AFFINE_SERVER_PORT}"
export AFFINE_SERVER_DATA="${DATA_MODE}"

affine-server--info() {
  echo "AFFiNE Server"
  echo "  Home:    ${AFFINE_DIR}"
  echo "  Port:    ${AFFINE_SERVER_PORT}"
  echo "  Data:    ${DATA_MODE}  (clean | seed via +seed | persist via +persist)"
  echo "  Starter: ${STARTER_FILE}"
  echo "  Stopper: ${STOPPER_FILE}"
  echo "  URL:     http://localhost:${AFFINE_SERVER_PORT}"
  echo "  Tree:    \$HOME/.affine"
}
PROFILE
chmod 644 "${PROFILE_FILE}"

cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /usr/local/lib/cb-affine-data.sh
cb_affine_init "${1:-}"
cb_affine_resolve_mode

if [[ ! -f "$AFFINE_DIR/dist/main.js" ]]; then
  echo "❌ AFFiNE Server is not installed at $AFFINE_DIR" >&2
  exit 1
fi

cb_affine_wait_deps

echo "Starting AFFiNE on http://localhost:${PORT} (data=${MODE})"
mkdir -p "$DATA_DIR"

case "$MODE" in
  clean)
    cb_affine_wipe_files
    cb_affine_wipe_db
    redis-cli FLUSHDB >/dev/null 2>&1 || true
    cb_affine_ensure_db
    cb_affine_prepare_files
    cb_affine_migrate
    ;;
  seed)
    cb_affine_wipe_db
    if cb_affine_has_dump; then
      cb_affine_restore
    else
      cb_affine_ensure_db
    fi
    cb_affine_prepare_files
    cb_affine_migrate
    ;;
  persist)
    if cb_affine_has_dump; then
      cb_affine_restore
    else
      cb_affine_ensure_db
    fi
    cb_affine_prepare_files
    cb_affine_migrate
    ;;
esac

echo "  Admin setup (first visit): http://localhost:${PORT}/admin/setup"
echo "  Host browser: http://localhost:${PORT}/  (globe pane cannot load /admin/js/)"

node ./dist/main.js &
affine_pid=$!
trap 'kill "$affine_pid" 2>/dev/null || true; [[ "$MODE" == persist ]] && cb_affine_dump; exit 0' TERM INT
wait "$affine_pid" || true
[[ "$MODE" == persist ]] && cb_affine_dump
STARTER
chmod 755 "${STARTER_FILE}"

cat > "${STOPPER_FILE}" <<'STOPPER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /usr/local/lib/cb-affine-data.sh
cb_affine_init "${1:-}"
cb_affine_resolve_mode
cb_affine_stop_server
if [[ "$MODE" == persist ]]; then
  echo "Dumping AFFiNE data to ${DATA_DIR} ..."
  cb_affine_dump
  echo "AFFiNE data saved (persist)."
fi
echo "AFFiNE Server stopped."
STOPPER
chmod 755 "${STOPPER_FILE}"

# ---- summary ----
echo ""
# Register a desktop icon that opens AFFiNE in a browser (desktop variants only).
ICON="applications-internet"
for candidate in favicon.svg favicon.ico icon.png logo.png; do
  found="$(find "$AFFINE_DIR/static" -maxdepth 3 -name "$candidate" -print -quit 2>/dev/null || true)"
  if [ -n "$found" ]; then ICON="$found"; break; fi
done
cb-web-icon.sh --id affine-server --name "AFFiNE" --icon "$ICON" \
  --port-env AFFINE_SERVER_PORT --port "${AFFINE_SERVER_PORT}" \
  --path / --start start-affine-server

echo "✅ AFFiNE Server installed."
echo "   Location: ${AFFINE_DIR}"
echo "   Port:     ${AFFINE_SERVER_PORT}"
echo "   Data:     ${DATA_MODE}"
echo "   Starter:  ${STARTER_FILE}"
echo "   Stopper:  ${STOPPER_FILE}"
echo ""
echo "ℹ️ Ready to use:"
echo "   start-affine-server [PORT]"
echo "   stop-affine-server"
echo "   Access: http://localhost:${AFFINE_SERVER_PORT}/admin/setup"
echo "   Host browser (not the globe pane): http://localhost:${AFFINE_SERVER_PORT}/"
echo "   Data: ${DATA_MODE}  (clean | +seed | +persist)"
echo "   Add +autostart to run it on boot, +expose to reach it from the host."
