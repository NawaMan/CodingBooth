#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Workspace-local setup: download WordPress core into /var/www/html and add a
# startup hook that creates the `wordpress` MySQL database on container boot.

set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar php-mysql
rm -rf /var/lib/apt/lists/*

echo "⬇️  Downloading WordPress core ..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL https://wordpress.org/latest.tar.gz -o "$TMP/wp.tar.gz"
tar -xzf "$TMP/wp.tar.gz" -C "$TMP"

# Replace the default Apache landing page with WordPress sources.
rm -f /var/www/html/index.html
cp -a "$TMP/wordpress/." /var/www/html/
chown -R www-data:www-data /var/www/html

# Startup hook: ensure the `wordpress` database exists once mysqld is up.
STARTUP_FILE="/usr/share/startup.d/60-cb-wordpress--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Wait briefly for mysqld (started by 50-cb-mysql--startup.sh).
for i in $(seq 1 30); do
  mysqladmin ping --silent 2>/dev/null && break
  sleep 1
done

mysql -u root -e "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
STARTUP
chmod 755 "$STARTUP_FILE"

echo ""
echo "✅ WordPress core installed at /var/www/html"
echo "   On container start: 'wordpress' database is created automatically."
echo "   Connect WordPress with:"
echo "     DB host: localhost"
echo "     DB user: \$USER (e.g. coder)"
echo "     DB pass: (empty)"
echo "     DB name: wordpress"
