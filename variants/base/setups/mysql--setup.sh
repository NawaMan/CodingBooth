#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0

Examples:
  $0    # install MySQL server + client

Notes:
- Installs MySQL server + client via apt
- The server is NOT started during build (Docker best practice)
- A startup script auto-starts mysqld on container start
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing MySQL ..."
apt-get update
apt-get install -y --no-install-recommends \
  mysql-server mysql-client libmysqlclient-dev
rm -rf /var/lib/apt/lists/*

# Ensure log directory exists with correct permissions
install -d -o mysql -g mysql -m 0755 /var/log/mysql
install -d -o mysql -g mysql -m 0755 /var/run/mysqld

# --- startup script: initialize and start mysqld ---
STARTUP_FILE="/usr/share/startup.d/50-cb-mysql--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

MYSQL_DATA="/var/lib/mysql"

# Ensure directories exist with correct permissions
sudo install -d -o mysql -g mysql -m 0755 /var/log/mysql
sudo install -d -o mysql -g mysql -m 0755 /var/run/mysqld

# Initialize if needed
if [ ! -d "$MYSQL_DATA/mysql" ]; then
  mysqld --initialize-insecure --user=mysql 2>/dev/null || true
fi

# Start server
mysqld_safe --user=mysql &
# Wait for it to be ready
for i in $(seq 1 30); do
  mysqladmin ping --silent 2>/dev/null && break
  sleep 1
done

# Create a user matching the container user (if not exists)
CUSER="${USER:-coder}"
mysql -u root -e "CREATE USER IF NOT EXISTS '${CUSER}'@'localhost'; GRANT ALL PRIVILEGES ON *.* TO '${CUSER}'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null || true
STARTUP
chmod 755 "$STARTUP_FILE"

INSTALLED_VERSION=$(mysql --version 2>/dev/null || echo "unknown")
echo ""
echo "✅ MySQL installed."
echo "   ${INSTALLED_VERSION}"
echo "   Server auto-starts on container boot via startup script."
echo ""
echo "ℹ️ Ready to use: mysql, mysqldump"
