#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--port <PORT>] [--user <USER>] [--pass <PASS>] [--db <DBNAME>] [--data <DIR>] [--run-foreground]

Environment overrides:
  MYSQL_PORT  (default: 3306)
  MYSQL_USER  (default: devuser)
  MYSQL_PASS  (default: devpass)
  MYSQL_DB    (default: devdb)
  MYSQL_DATA  (default: /opt/mysqldata)

Notes:
- For development only (binds to 0.0.0.0, simple auth).
- Initializes a separate data dir; does not touch the system default.
- Starts mysqld directly (no systemd). Use --run-foreground to keep it attached.

Examples:
  $0
  $0 --port 3307 --user alice --pass secret --db mydb --data /data/mysql
  MYSQL_PORT=3333 MYSQL_USER=bob MYSQL_PASS=pwd MYSQL_DB=foo $0 --run-foreground
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults from env ---
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-devuser}"
MYSQL_PASS="${MYSQL_PASS:-devpass}"
MYSQL_DB="${MYSQL_DB:-devdb}"
MYSQL_DATA="${MYSQL_DATA:-/opt/mysqldata}"
RUN_FOREGROUND=0

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) shift; MYSQL_PORT="${1:-}"; shift ;;
    --user) shift; MYSQL_USER="${1:-}"; shift ;;
    --pass) shift; MYSQL_PASS="${1:-}"; shift ;;
    --db)   shift; MYSQL_DB="${1:-}"; shift ;;
    --data) shift; MYSQL_DATA="${1:-}"; shift ;;
    --run-foreground) RUN_FOREGROUND=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# --- install server/client ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
# On Ubuntu 24.04 this installs MySQL Community Server (8.x). If your base image resolves to MariaDB, the commands still work.
apt-get install -y --no-install-recommends mysql-server mysql-client
rm -rf /var/lib/apt/lists/*

# --- ensure mysql user exists & data dir prepared ---
id mysql >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin mysql || true
mkdir -p "$MYSQL_DATA"
chown -R mysql:mysql "$MYSQL_DATA"
chmod 0750 "$MYSQL_DATA"

# --- figure out paths ---
MYSQLD_BIN="$(command -v mysqld)"
MYSQL_BIN="$(command -v mysql)"
MYSQLADMIN_BIN="$(command -v mysqladmin)"
SOCKET_PATH="${MYSQL_DATA%/}/mysqld.sock"
PID_FILE="${MYSQL_DATA%/}/mysqld.pid"
ERR_LOG="${MYSQL_DATA%/}/mysqld.err"

# --- initialize if empty ---
if [ -z "$(ls -A "$MYSQL_DATA" 2>/dev/null)" ]; then
  echo "[init] Initializing data dir at $MYSQL_DATA ..."
  # --initialize-insecure: creates system tables, root has no password initially
  "$MYSQLD_BIN" --initialize-insecure \
    --datadir="$MYSQL_DATA" \
    --user=mysql \
    --basedir=/usr \
    --log-error="$ERR_LOG"
fi

# --- start server (background unless --run-foreground) ---
MYSQLD_ARGS=(
  "--datadir=$MYSQL_DATA"
  "--user=mysql"
  "--port=$MYSQL_PORT"
  "--bind-address=0.0.0.0"
  "--socket=$SOCKET_PATH"
  "--pid-file=$PID_FILE"
  "--skip-networking=0"
  "--log-error=$ERR_LOG"
)

echo "[start] Starting mysqld on 0.0.0.0:${MYSQL_PORT} (data: $MYSQL_DATA)"
if [[ "$RUN_FOREGROUND" -eq 1 ]]; then
  # Foreground mode (keeps container alive)
  exec "$MYSQLD_BIN" "${MYSQLD_ARGS[@]}"
else
  # Background
  "$MYSQLD_BIN" "${MYSQLD_ARGS[@]}" --daemonize
fi

# --- wait for server to accept connections ---
echo -n "[wait] Waiting for server to be ready"
for i in {1..60}; do
  if "$MYSQLADMIN_BIN" --protocol=socket --socket="$SOCKET_PATH" ping >/dev/null 2>&1; then
    echo " ... ready."
    break
  fi
  echo -n "."
  sleep 1
done

# --- set root password (only if not set yet) ---
# Try root with no password via socket
if "$MYSQL_BIN" --protocol=socket --socket="$SOCKET_PATH" -uroot -e "SELECT 1;" >/dev/null 2>&1; then
  echo "[auth] Securing root account ..."
  "$MYSQL_BIN" --protocol=socket --socket="$SOCKET_PATH" -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASS}';
FLUSH PRIVILEGES;
SQL
fi

# --- create dev user/db (idempotent) ---
echo "[provision] Creating user '${MYSQL_USER}' and db '${MYSQL_DB}' (if missing) ..."
"$MYSQL_BIN" --protocol=socket --socket="$SOCKET_PATH" -uroot -p"${MYSQL_PASS}" <<SQL
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
SQL

cat <<EOM

✅ MySQL ready for development
  Host:      0.0.0.0
  Port:      ${MYSQL_PORT}
  User:      ${MYSQL_USER}
  Password:  ${MYSQL_PASS}
  Database:  ${MYSQL_DB}
  Data dir:  ${MYSQL_DATA}
  Socket:    ${SOCKET_PATH}

Try connecting:
  mysql -h 127.0.0.1 -P ${MYSQL_PORT} -u ${MYSQL_USER} -p${MYSQL_PASS} ${MYSQL_DB}

Stop server:
  mysqladmin -h 127.0.0.1 -P ${MYSQL_PORT} -u root -p${MYSQL_PASS} shutdown
  # or: mysqld --datadir="${MYSQL_DATA}" --pid-file="${PID_FILE}" --shutdown-timeout=30 --console

Tip:
  Use --run-foreground in containers if you want mysqld to stay attached.
EOM
