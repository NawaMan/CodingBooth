#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--with-php]

Examples:
  $0              # install apache2 only
  $0 --with-php   # install apache2 + libapache2-mod-php (mod_php enabled)

Notes:
- Installs the Apache HTTP Server via apt
- The server is NOT started during build (Docker best practice)
- A startup script auto-starts apache2 on container start
- With --with-php, mod_php is enabled so .php files are served by Apache directly
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

WITH_PHP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-php) WITH_PHP=true; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing Apache HTTP Server ..."
apt-get update

if $WITH_PHP; then
  apt-get install -y --no-install-recommends apache2 libapache2-mod-php
else
  apt-get install -y --no-install-recommends apache2
fi
rm -rf /var/lib/apt/lists/*

# --- startup script: start apache2 ---
STARTUP_FILE="/usr/share/startup.d/55-cb-apache--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
# Best-effort startup. Don't take down container init on transient errors.
set +e

# Apache needs these dirs to exist at runtime
sudo install -d -o root -g root -m 0755 /var/run/apache2  2>/dev/null
sudo install -d -o root -g root -m 0755 /var/lock/apache2 2>/dev/null
sudo install -d -o www-data -g www-data -m 0755 /var/log/apache2 2>/dev/null

# Source apache envvars (sets APACHE_RUN_USER, etc.)
# shellcheck disable=SC1091
source /etc/apache2/envvars 2>/dev/null

# Start apache in daemon mode, best-effort.
sudo apachectl start 2>/dev/null
exit 0
STARTUP
chmod 755 "$STARTUP_FILE"

INSTALLED_VERSION=$(apache2 -v 2>/dev/null | head -1 || echo "unknown")
echo ""
echo "✅ Apache HTTP Server installed."
echo "   ${INSTALLED_VERSION}"
echo "   Server auto-starts on container boot via startup script."
if $WITH_PHP; then
  echo "   mod_php enabled — drop .php files in /var/www/html"
fi
echo ""
echo "ℹ️ Default DocumentRoot: /var/www/html"
