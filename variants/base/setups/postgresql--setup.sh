#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <ver>]

Examples:
  $0                   # install default PostgreSQL
  $0 --version 16      # pin to PostgreSQL 16

Notes:
- Installs PostgreSQL server + client via apt
- The server is NOT started during build (Docker best practice)
- A startup script auto-initializes and starts the server on container start
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

PG_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; PG_VERSION="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# "latest" means "whatever the distro ships" — same as passing nothing. Without
# this it would reach apt as the literal package name "postgresql-latest".
[[ "$PG_VERSION" == "latest" ]] && PG_VERSION=""

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing PostgreSQL ..."
apt-get update

if [[ -n "$PG_VERSION" ]]; then
  apt-get install -y --no-install-recommends \
    "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}" libpq-dev
else
  apt-get install -y --no-install-recommends \
    postgresql postgresql-client libpq-dev
fi

rm -rf /var/lib/apt/lists/*

# --- build-time: create CodingBooth PostgreSQL config files ---
CB_PG_CONF_DIR="/opt/codingbooth/postgresql"
mkdir -p "$CB_PG_CONF_DIR"

cat > "$CB_PG_CONF_DIR/pg_hba.conf" <<'PGHBA'
# CodingBooth: trust local connections (dev environment)
local   all   all                 trust
host    all   all   127.0.0.1/32  trust
host    all   all   ::1/128       trust
PGHBA

cat > "$CB_PG_CONF_DIR/postgresql-booth.conf" <<'PGCONF'
# CodingBooth: PostgreSQL overrides for dev environment
listen_addresses = 'localhost'
PGCONF

# --- startup script: init DB cluster and start server ---
STARTUP_FILE="/usr/share/startup.d/50-cb-postgresql--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

CB_PG_CONF_DIR="/opt/codingbooth/postgresql"

# Find the installed PG version
PG_VER=$(pg_config --version 2>/dev/null | grep -oP '\d+' | head -1)
PG_DATA="/var/lib/postgresql/${PG_VER}/main"

# Initialize cluster if not exists
if [ ! -d "$PG_DATA" ] || [ ! -f "$PG_DATA/PG_VERSION" ]; then
  sudo -u postgres /usr/lib/postgresql/${PG_VER}/bin/initdb -D "$PG_DATA" 2>/dev/null || true
fi

# Apply CodingBooth configs (idempotent)
if [ -f "$CB_PG_CONF_DIR/pg_hba.conf" ]; then
  sudo -u postgres cp "$CB_PG_CONF_DIR/pg_hba.conf" "$PG_DATA/pg_hba.conf"
fi
if [ -f "$CB_PG_CONF_DIR/postgresql-booth.conf" ] && \
   ! grep -q "include 'postgresql-booth.conf'" "$PG_DATA/postgresql.conf" 2>/dev/null; then
  sudo -u postgres cp "$CB_PG_CONF_DIR/postgresql-booth.conf" "$PG_DATA/postgresql-booth.conf"
  echo "include 'postgresql-booth.conf'" | sudo -u postgres tee -a "$PG_DATA/postgresql.conf" > /dev/null
fi

# Start server
sudo -u postgres /usr/lib/postgresql/${PG_VER}/bin/pg_ctl \
  -D "$PG_DATA" -l /var/log/postgresql/postgresql.log start 2>/dev/null || true

# Create a user matching the container user (if not exists)
CUSER="${USER:-coder}"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${CUSER}'" 2>/dev/null \
  | grep -q 1 \
  || sudo -u postgres createuser -s "${CUSER}" 2>/dev/null || true
STARTUP
chmod 755 "$STARTUP_FILE"

INSTALLED_VERSION=$(pg_config --version 2>/dev/null || echo "unknown")
echo ""
echo "✅ ${INSTALLED_VERSION} installed."
echo "   Server auto-starts on container boot via startup script."
echo ""
echo "ℹ️ Ready to use: psql, createdb, pg_dump"
