#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--with-php-fpm]

Examples:
  $0                  # install nginx only
  $0 --with-php-fpm   # install nginx + php-fpm and route .php to fpm via default site

Notes:
- Installs nginx via apt
- The server is NOT started during build (Docker best practice)
- A startup script auto-starts nginx on container start
- With --with-php-fpm, php-fpm is installed and the default site is configured to
  pass .php files to fpm over the unix socket /run/php/php-fpm.sock
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

WITH_FPM=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-php-fpm) WITH_FPM=true; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing nginx ..."
apt-get update

if $WITH_FPM; then
  apt-get install -y --no-install-recommends nginx php-fpm
else
  apt-get install -y --no-install-recommends nginx
fi
rm -rf /var/lib/apt/lists/*

# Configure default site to pass .php files to php-fpm if requested.
if $WITH_FPM; then
  FPM_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1 || true)
  if [[ -z "$FPM_SOCK" ]]; then
    # Discover socket path from installed php-fpm pool config (sock created at runtime).
    PHP_VER=$(ls /etc/php/ 2>/dev/null | head -1 || echo "")
    FPM_SOCK="/run/php/php${PHP_VER}-fpm.sock"
  fi

  cat >/etc/nginx/sites-available/default <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${FPM_SOCK};
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX
fi

# --- startup script: start nginx (and php-fpm if installed) ---
STARTUP_FILE="/usr/share/startup.d/55-cb-nginx--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
# Best-effort startup. Don't take down container init on transient errors.
set +e

# Start php-fpm if it's installed (LEMP usage).
if command -v php-fpm >/dev/null 2>&1 || ls /usr/sbin/php-fpm* >/dev/null 2>&1; then
  PHP_FPM_BIN=$(ls /usr/sbin/php-fpm* 2>/dev/null | head -1 || command -v php-fpm)
  if [[ -n "$PHP_FPM_BIN" ]]; then
    sudo install -d -o root -g root -m 0755 /run/php 2>/dev/null
    sudo "$PHP_FPM_BIN" --daemonize 2>/dev/null
  fi
fi

# Start nginx in daemon mode, best-effort.
sudo install -d -o root -g root -m 0755 /var/log/nginx 2>/dev/null
sudo nginx 2>/dev/null
exit 0
STARTUP
chmod 755 "$STARTUP_FILE"

INSTALLED_VERSION=$(nginx -v 2>&1 | head -1 || echo "unknown")
echo ""
echo "✅ nginx installed."
echo "   ${INSTALLED_VERSION}"
echo "   Server auto-starts on container boot via startup script."
if $WITH_FPM; then
  echo "   php-fpm wired to default site — drop .php files in /var/www/html"
fi
echo ""
echo "ℹ️ Default DocumentRoot: /var/www/html"
