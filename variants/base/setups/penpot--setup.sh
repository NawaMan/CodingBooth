#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [PORT]

Arguments:
  PORT  Port for the Penpot web UI (default: 19001)

Examples:
  $0           # install with default port 19001
  $0 9001      # official upstream compose port

Prerequisites:
- Penpot backend/frontend must be copied into /opt/penpot
  (typically via COPY --from=penpotapp/backend:<tag> and penpotapp/frontend:<tag>)
- PostgreSQL and Redis at runtime (the template requires them)

Notes:
- Creates a starter script at /usr/local/bin/start-penpot
- Penpot web UI is accessible at http://localhost:<PORT>
- The server is NOT started during build; add the autostart extension
- PNG/PDF export needs the exporter extension
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
PENPOT_PORT="${1:-19001}"
PENPOT_DIR="/opt/penpot"
BACKEND_DIR="${PENPOT_DIR}/backend"
FRONTEND_DIR="${PENPOT_DIR}/frontend"
ASSETS_DIR="/opt/data/assets"
PROFILE_FILE="/etc/profile.d/70-cb-penpot--profile.sh"
STARTER_FILE="/usr/local/bin/start-penpot"
NGINX_TEMPLATE="${PENPOT_DIR}/nginx.conf.template"

# ---- verify Penpot is present ----
if [[ ! -f "$BACKEND_DIR/run.sh" && ! -f "$BACKEND_DIR/penpot.jar" ]]; then
  echo "❌ Penpot backend not found at $BACKEND_DIR"
  echo "   Use COPY --from=penpotapp/backend:<tag> /opt/penpot/backend /opt/penpot/backend"
  exit 1
fi
if [[ ! -d "$FRONTEND_DIR" || ! -f "$FRONTEND_DIR/index.html" ]]; then
  echo "❌ Penpot frontend not found at $FRONTEND_DIR"
  echo "   Use COPY --from=penpotapp/frontend:<tag> /var/www/app /opt/penpot/frontend"
  exit 1
fi

# Official images put the JRE at /opt/jre; older run.sh may call /opt/jdk/bin/java.
if [[ -d /opt/jre && ! -e /opt/jdk ]]; then
  ln -sfn /opt/jre /opt/jdk
fi

# ---- runtime libraries (fonts / ImageMagick helpers) + a dedicated nginx ----
export DEBIAN_FRONTEND=noninteractive
echo "• Installing nginx and Penpot runtime libraries ..."
apt-get update
apt-get install -y --no-install-recommends \
  nginx \
  ca-certificates \
  curl \
  fontconfig \
  libfontconfig1 \
  libfreetype6 \
  libglib2.0-0 \
  libgomp1 \
  libheif1 \
  libjpeg-turbo8 \
  liblcms2-2 \
  libopenexr-3-1-30 \
  libopenjp2-7 \
  libpng16-16 \
  librsvg2-2 \
  libtiff6 \
  libwebp7 \
  libwebpdemux2 \
  libwebpmux3 \
  libxml2 \
  libzstd1 \
  openssl \
  python3 \
  tzdata
rm -rf /var/lib/apt/lists/*

mkdir -p "$ASSETS_DIR" "$PENPOT_DIR"
chmod -R a+rX "$PENPOT_DIR" /opt/jre /opt/imagick 2>/dev/null || true
chmod a+rwx "$ASSETS_DIR"
if id coder >/dev/null 2>&1; then
  chown -R coder:coder "$PENPOT_DIR" "$ASSETS_DIR" || true
  chown -R coder:coder /opt/jre /opt/imagick 2>/dev/null || true
fi

# ---- nginx template (own process, own port — does not touch the booth's nginx) ----
cat > "$NGINX_TEMPLATE" <<'NGINX'
worker_processes 1;
pid /tmp/penpot-nginx.pid;
error_log /tmp/penpot-nginx-error.log warn;
daemon off;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /tmp/penpot-nginx-access.log;
    client_max_body_size 350m;
    client_body_temp_path /tmp/penpot-nginx/client_temp;
    proxy_temp_path       /tmp/penpot-nginx/proxy_temp;
    fastcgi_temp_path     /tmp/penpot-nginx/fastcgi_temp;
    uwsgi_temp_path       /tmp/penpot-nginx/uwsgi_temp;
    scgi_temp_path        /tmp/penpot-nginx/scgi_temp;
    sendfile on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen __PENPOT_PORT__ default_server;
        server_name _;
        charset utf-8;
        root /opt/penpot/frontend;

        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;

        location /assets {
            proxy_pass http://127.0.0.1:6060/assets;
        }
        location /api/export {
            proxy_pass http://127.0.0.1:6061;
        }
        location /api {
            proxy_pass http://127.0.0.1:6060/api;
            proxy_buffering off;
        }
        location /readyz {
            access_log off;
            proxy_pass http://127.0.0.1:6060$request_uri;
        }
        location /ws/notifications {
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_pass http://127.0.0.1:6060/ws/notifications;
        }
        location / {
            try_files $uri /index.html =404;
        }
    }
}
NGINX
chmod 644 "$NGINX_TEMPLATE"

# ---- create profile script ----
cat > "${PROFILE_FILE}" <<PROFILE
# Penpot environment
export PENPOT_HOME="${PENPOT_DIR}"
export PENPOT_PORT="${PENPOT_PORT}"
export PENPOT_URL="http://localhost:${PENPOT_PORT}"
if [[ -d /opt/jre/bin ]]; then
  case ":\$PATH:" in
    *":/opt/jre/bin:"*) ;;
    *) export PATH="/opt/jre/bin:\$PATH" ;;
  esac
fi
if [[ -d /opt/imagick/bin ]]; then
  case ":\$PATH:" in
    *":/opt/imagick/bin:"*) ;;
    *) export PATH="/opt/imagick/bin:\$PATH" ;;
  esac
  export LD_LIBRARY_PATH="/opt/imagick/lib/deps\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
fi

penpot--info() {
  echo "Penpot"
  echo "  Home:    ${PENPOT_DIR}"
  echo "  Port:    ${PENPOT_PORT}"
  echo "  Starter: ${STARTER_FILE}"
  echo "  URL:     http://localhost:${PENPOT_PORT}"
  echo "  Assets:  ${ASSETS_DIR}"
}
PROFILE
chmod 644 "${PROFILE_FILE}"

# ---- create starter script (manual foreground launch) ----
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-__PENPOT_PORT_DEFAULT__}"
BACKEND_DIR="/opt/penpot/backend"
FRONTEND_DIR="/opt/penpot/frontend"
ASSETS_DIR="/opt/data/assets"
NGINX_TEMPLATE="/opt/penpot/nginx.conf.template"
NGINX_CONF="/tmp/penpot-nginx.conf"
BACKEND_LOG="/tmp/penpot-backend.log"
EXPORTER_LOG="/tmp/penpot-exporter.log"

export JAVA_HOME="${JAVA_HOME:-/opt/jre}"
export PATH="${JAVA_HOME}/bin:/opt/imagick/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/imagick/lib/deps${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [[ ! -f "$BACKEND_DIR/run.sh" && ! -f "$BACKEND_DIR/penpot.jar" ]]; then
  echo "❌ Penpot backend is not installed at $BACKEND_DIR" >&2
  exit 1
fi

mkdir -p "$ASSETS_DIR" /tmp/penpot-nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}

# Redis is installed by its template but does not auto-start; PostgreSQL does.
if command -v redis-server >/dev/null 2>&1; then
  if ! redis-cli ping 2>/dev/null | grep -qx PONG; then
    REDIS_DATA="${HOME}/.redis/data"
    mkdir -p "$REDIS_DATA" "${HOME}/.redis/log"
    echo "• Starting Redis ..."
    redis-server --dir "$REDIS_DATA" --daemonize yes --port 6379 \
      --logfile "${HOME}/.redis/log/redis.log"
  fi
fi

echo "• Waiting for PostgreSQL and Redis ..."
ready=0
for _ in $(seq 1 60); do
  pg_ok=0
  rd_ok=0
  if command -v pg_isready >/dev/null 2>&1 && pg_isready -q; then pg_ok=1; fi
  if command -v redis-cli >/dev/null 2>&1 && redis-cli ping 2>/dev/null | grep -qx PONG; then rd_ok=1; fi
  if [[ "$pg_ok" -eq 1 && "$rd_ok" -eq 1 ]]; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" -ne 1 ]]; then
  echo "❌ PostgreSQL and Redis must be running (select postgresql and redis)." >&2
  echo "   pg_isready / redis-cli ping did not succeed within 60s." >&2
  exit 1
fi

if command -v createdb >/dev/null 2>&1; then
  createdb penpot 2>/dev/null || true
fi

SECRET_FILE="${ASSETS_DIR}/.cb-secret-key"
if [[ ! -s "$SECRET_FILE" ]]; then
  openssl rand -base64 64 | tr -d '\n' > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
fi
PENPOT_SECRET_KEY="$(cat "$SECRET_FILE")"

CUSER="${USER:-coder}"
export PENPOT_SECRET_KEY
export PENPOT_PUBLIC_URI="${PENPOT_PUBLIC_URI:-http://localhost:${PORT}}"
export PENPOT_FLAGS="${PENPOT_FLAGS:-disable-email-verification disable-smtp enable-login-with-password enable-registration disable-secure-session-cookies disable-telemetry enable-prepl-server}"
export PENPOT_DATABASE_URI="${PENPOT_DATABASE_URI:-postgresql://127.0.0.1/penpot}"
export PENPOT_DATABASE_USERNAME="${PENPOT_DATABASE_USERNAME:-${CUSER}}"
export PENPOT_DATABASE_PASSWORD="${PENPOT_DATABASE_PASSWORD:-}"
export PENPOT_REDIS_URI="${PENPOT_REDIS_URI:-redis://127.0.0.1/0}"
export PENPOT_OBJECTS_STORAGE_BACKEND="${PENPOT_OBJECTS_STORAGE_BACKEND:-fs}"
export PENPOT_OBJECTS_STORAGE_FS_DIRECTORY="${PENPOT_OBJECTS_STORAGE_FS_DIRECTORY:-${ASSETS_DIR}}"
export PENPOT_TELEMETRY_ENABLED="${PENPOT_TELEMETRY_ENABLED:-false}"
export PENPOT_HTTP_SERVER_MAX_BODY_SIZE="${PENPOT_HTTP_SERVER_MAX_BODY_SIZE:-367001600}"

# Stamp frontend flags so the SPA matches the backend.
CONFIG_JS="${FRONTEND_DIR}/js/config.js"
if [[ -f "$CONFIG_JS" ]]; then
  if grep -q '^//var penpotFlags' "$CONFIG_JS" 2>/dev/null; then
    sed -i "s|^//var penpotFlags = .*;|var penpotFlags = \"${PENPOT_FLAGS}\";|" "$CONFIG_JS"
  elif grep -q '^var penpotFlags' "$CONFIG_JS" 2>/dev/null; then
    sed -i "s|^var penpotFlags = .*;|var penpotFlags = \"${PENPOT_FLAGS}\";|" "$CONFIG_JS"
  else
    echo "var penpotFlags = \"${PENPOT_FLAGS}\";" >> "$CONFIG_JS"
  fi
  if ! grep -q 'penpotPublicURI' "$CONFIG_JS" 2>/dev/null; then
    echo "var penpotPublicURI = \"${PENPOT_PUBLIC_URI}\";" >> "$CONFIG_JS"
  fi
fi

# Backend on :6060 — skip if a previous start-penpot left it running.
if ! curl -sf -o /dev/null "http://127.0.0.1:6060/readyz" 2>/dev/null; then
  echo "• Starting Penpot backend ..."
  (
    cd "$BACKEND_DIR"
    if [[ -x ./run.sh || -f ./run.sh ]]; then
      exec bash ./run.sh
    else
      exec java \
        -Djava.util.logging.manager=org.apache.logging.log4j.jul.LogManager \
        -Dlog4j2.configurationFile=log4j2.xml \
        -XX:-OmitStackTraceInFastThrow \
        -Dpolyglot.engine.WarnInterpreterOnly=false \
        --enable-preview \
        -jar penpot.jar -m app.main
    fi
  ) >> "$BACKEND_LOG" 2>&1 &
  disown || true
fi

echo "• Waiting for Penpot backend on :6060 ..."
backend_ready=0
for _ in $(seq 1 90); do
  if curl -sf -o /dev/null "http://127.0.0.1:6060/readyz" 2>/dev/null; then
    backend_ready=1
    break
  fi
  sleep 1
done
if [[ "$backend_ready" -ne 1 ]]; then
  echo "⚠️  Backend did not answer /readyz within 90s — starting the UI anyway."
  echo "   Last backend log lines:"
  tail -n 20 "$BACKEND_LOG" 2>/dev/null || true
fi

# Optional exporter (copied by the exporter extension).
if [[ -f /opt/penpot/exporter/app.js ]]; then
  if ! curl -sf -o /dev/null "http://127.0.0.1:6061/" 2>/dev/null; then
    echo "• Starting Penpot exporter ..."
    export PENPOT_INTERNAL_URI="http://127.0.0.1:${PORT}"
    export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/penpot/browsers}"
    if [[ -d /opt/penpot-exporter-node/bin ]]; then
      export PATH="/opt/penpot-exporter-node/bin:${PATH}"
    fi
    (
      cd /opt/penpot/exporter
      if command -v xvfb-run >/dev/null 2>&1 && [[ -z "${DISPLAY:-}" ]]; then
        exec xvfb-run -a node app.js
      else
        exec node app.js
      fi
    ) >> "$EXPORTER_LOG" 2>&1 &
    disown || true
  fi
fi

sed "s/__PENPOT_PORT__/${PORT}/g" "$NGINX_TEMPLATE" > "$NGINX_CONF"

echo "Starting Penpot on http://localhost:$PORT ..."
echo "  (first browser visit creates the account — email verification is off)"
exec nginx -c "$NGINX_CONF"
STARTER
sed -i "s/__PENPOT_PORT_DEFAULT__/${PENPOT_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
ICON="applications-internet"
for candidate in favicon.svg favicon.ico images/favicon.png images/favicon.svg icon.png logo.png; do
  if [[ -f "$FRONTEND_DIR/$candidate" ]]; then ICON="$FRONTEND_DIR/$candidate"; break; fi
  found="$(find "$FRONTEND_DIR" -maxdepth 3 -name "$(basename "$candidate")" -print -quit 2>/dev/null || true)"
  if [[ -n "$found" ]]; then ICON="$found"; break; fi
done
cb-web-icon.sh --id penpot --name "Penpot" --icon "$ICON" \
  --port-env PENPOT_PORT --port "${PENPOT_PORT}" \
  --path / --start start-penpot

echo "✅ Penpot installed."
echo "   Location: ${PENPOT_DIR}"
echo "   Port:     ${PENPOT_PORT}"
echo "   Starter:  ${STARTER_FILE}"
echo "   Assets:   ${ASSETS_DIR}  (volume booth-penpot-assets)"
echo ""
echo "ℹ️ Ready to use:"
echo "   start-penpot [PORT]"
echo "   Access: http://localhost:${PENPOT_PORT}"
echo "   First visit in the browser creates the account (no email required)."
echo "   Add +autostart to run it on boot, +expose to reach it from the host."
echo "   Add +exporter for PNG/PDF export (Chromium, ~650MB)."
