#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--port <PORT>] [--user <USER>] [--pass <PASS>] [--data <DIR>]

Environment overrides:
  PG_PORT   (default: 5432)
  PG_USER   (default: devuser)
  PG_PASS   (default: devpass)
  PG_DATA   (default: /opt/pgdata)

Examples:
  $0                       # installs PostgreSQL, runs on 5432 with devuser/devpass
  PG_PORT=5555 $0          # use env var
  $0 --port 5555 --user foo --pass bar --data /data/postgres
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults ---
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-devuser}"
PG_PASS="${PG_PASS:-devpass}"
PG_DATA="${PG_DATA:-/opt/pgdata}"

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) shift; PG_PORT="${1:-}"; shift ;;
    --user) shift; PG_USER="${1:-}"; shift ;;
    --pass) shift; PG_PASS="${1:-}"; shift ;;
    --data) shift; PG_DATA="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# --- install ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends postgresql postgresql-contrib
rm -rf /var/lib/apt/lists/*

# --- setup cluster dir ---
mkdir -p "$PG_DATA"
chown -R postgres:postgres "$PG_DATA"

# --- initdb ---
sudo -u postgres /usr/lib/postgresql/*/bin/initdb -D "$PG_DATA"

# --- configure ---
PG_CONF="$PG_DATA/postgresql.conf"
PG_HBA="$PG_DATA/pg_hba.conf"

# listen on all addresses
echo "listen_addresses = '*'" >> "$PG_CONF"
echo "port = $PG_PORT" >> "$PG_CONF"

# allow password auth
cat >>"$PG_HBA" <<EOF
host all all 0.0.0.0/0 md5
host all all ::/0 md5
EOF

# --- start server ---
echo "▶ Starting PostgreSQL..."
sudo -u postgres /usr/lib/postgresql/*/bin/pg_ctl -D "$PG_DATA" -o "-p $PG_PORT" -w start

# --- create user & db ---
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE USER $PG_USER WITH SUPERUSER PASSWORD '$PG_PASS';"
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$PG_USER'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE DATABASE $PG_USER OWNER $PG_USER;"
fi

cat <<EOM

✅ PostgreSQL ready for development
  Host:      0.0.0.0
  Port:      $PG_PORT
  User:      $PG_USER
  Password:  $PG_PASS
  Data dir:  $PG_DATA

Try connecting:
  psql -h localhost -p $PG_PORT -U $PG_USER $PG_USER

Stop server:
  sudo -u postgres /usr/lib/postgresql/*/bin/pg_ctl -D "$PG_DATA" stop

EOM
