#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# booth-message-wrapper--setup.sh
#
# Installs the shared booth message wrapper infrastructure:
# 1. The overlay HTML/CSS/JS snippet (shared across all variants)
# 2. A generic nginx config template for wrapping any variant service
# 3. The booth-message-api-server (bash+socat for variants without Python)
# 4. A generic start-wrapped script that launches nginx in front of any service
#
# Each variant that wants the wrapper calls its own start-<variant>-wrapped
# which sets INNER_CMD and INNER_PORT, then delegates to start-booth-wrapped.
# -----------------------------------------------------------------------------

set -euo pipefail

WRAPPER_DIR="/usr/local/share/booth-message-wrapper"
mkdir -p "${WRAPPER_DIR}"

# ── Copy the shared overlay HTML ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "${SCRIPT_DIR}/booth-message-overlay.html" "${WRAPPER_DIR}/overlay.html"
cp "${SCRIPT_DIR}/booth-message-api-server" "${WRAPPER_DIR}/booth-message-api-server"
chmod +x "${WRAPPER_DIR}/booth-message-api-server"
cp "${SCRIPT_DIR}/booth-lifecycle-watcher" "${WRAPPER_DIR}/booth-lifecycle-watcher"
chmod +x "${WRAPPER_DIR}/booth-lifecycle-watcher"
cp "${SCRIPT_DIR}/booth-timer-notifier" "${WRAPPER_DIR}/booth-timer-notifier"
chmod +x "${WRAPPER_DIR}/booth-timer-notifier"

# ── Wrapper HTML template ──
# The variant start script sets IFRAME_SRC before generating the page.
cat > "${WRAPPER_DIR}/wrapper.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${BOOTH_CONTAINER_NAME} (${BOOTH_HOST_PORT})</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; overflow: hidden; background: #111; }
  iframe#booth-inner { width: 100%; height: 100%; border: none; }
</style>
</head>
<body>
<iframe id="booth-inner" src="${IFRAME_SRC}"></iframe>
<script>
window.BOOTH_SHOW_RUN_TIME="${BOOTH_SHOW_RUN_TIME}";
window.BOOTH_SHOW_COUNT_DOWN="${BOOTH_SHOW_COUNT_DOWN}";
</script>
${OVERLAY_HTML}
</body>
</html>
HTMLEOF

# ── nginx config template ──
cat > "${WRAPPER_DIR}/nginx.conf.template" <<'NGINXEOF'
worker_processes auto;
pid /tmp/nginx-booth-wrapper.pid;
error_log /tmp/nginx-booth-wrapper-error.log warn;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /tmp/nginx-booth-wrapper-access.log;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    client_max_body_size 50m;
    client_body_temp_path /tmp/nginx/body;
    proxy_temp_path /tmp/nginx/proxy;
    fastcgi_temp_path /tmp/nginx/fastcgi;
    uwsgi_temp_path /tmp/nginx/uwsgi;
    scgi_temp_path /tmp/nginx/scgi;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    # Map: if _booth_inner query param is present, proxy root to inner service
    # Otherwise redirect root to /booth wrapper page
    map $arg__booth_inner $root_action {
        default  "redirect";
        "~."     "proxy";
    }

    server {
        listen ${OUTER_PORT};
        server_name _;
        absolute_redirect off;

        # Wrapper page
        location = /booth {
            alias ${SERVE_DIR}/index.html;
            default_type text/html;
        }

        # Booth liveness — proxies to inner service; 2xx/3xx/4xx → 200, 5xx/timeout → unhealthy.
        location = /__booth/health {
            access_log off;
            proxy_pass http://127.0.0.1:${INNER_PORT}/;
            proxy_connect_timeout 2s;
            proxy_read_timeout 3s;
            proxy_intercept_errors on;
            error_page 301 302 303 304 307 308 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 422 429 =200 @__booth_alive;
        }
        location @__booth_alive {
            internal;
            default_type text/plain;
            add_header Cache-Control "no-store" always;
            return 200 "ok $time_iso8601\n";
        }

        # Booth metadata — always 200, independent of inner service.
        location = /__booth/info {
            access_log off;
            default_type application/json;
            return 200 '{"booth":"${BOOTH_CONTAINER_NAME}","variant":"${BOOTH_VARIANT_TAG}","version":"${BOOTH_VERSION_TAG}","port":"${BOOTH_HOST_PORT}"}\n';
        }

        # Message API
        location /booth-messages/api/ {
            proxy_pass http://127.0.0.1:${API_PORT};
            proxy_http_version 1.1;
            proxy_set_header Host $http_host;
            proxy_buffering off;
        }

        # Root — redirect to /booth unless _booth_inner is set
        location = / {
            if ($root_action = "proxy") {
                proxy_pass http://127.0.0.1:${INNER_PORT};
                break;
            }
            return 302 /booth;
        }

        # Everything else — proxy to the inner service
        location / {
            proxy_pass http://127.0.0.1:${INNER_PORT};
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 24h;
            proxy_buffering off;
        }
    }
}
NGINXEOF

# ── Generic wrapper start script ──
cat > /usr/local/bin/start-booth-wrapped <<'STARTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Required env vars (set by the variant-specific start-*-wrapped script):
#   INNER_CMD      — command to start the inner service (e.g., "start-codeserver 19999")
#   INNER_PORT     — port the inner service listens on
#   IFRAME_SRC     — URL path for the iframe (e.g., "/" or "/lab")

OUTER_PORT=${BOOTH_CODE_PORT:-10000}
API_PORT=${BOOTH_MSG_API_PORT:-10007}
WRAPPER_DIR=/usr/local/share/booth-message-wrapper
NGINX_CONFIG=/tmp/nginx-booth-wrapper.conf
SERVE_DIR=/tmp/booth-wrapper-serve

IFRAME_SRC="${IFRAME_SRC:-/}"

mkdir -p "$SERVE_DIR"
mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi

# Generate wrapper HTML
export BOOTH_CONTAINER_NAME="${BOOTH_CONTAINER_NAME:-CodingBooth}"
export BOOTH_HOST_PORT="${BOOTH_HOST_PORT:-$OUTER_PORT}"
export IFRAME_SRC
export BOOTH_SHOW_RUN_TIME="${BOOTH_SHOW_RUN_TIME:-}"
export BOOTH_SHOW_COUNT_DOWN="${BOOTH_SHOW_COUNT_DOWN:-}"
OVERLAY_HTML=$(cat "$WRAPPER_DIR/overlay.html")
export OVERLAY_HTML
envsubst '${BOOTH_CONTAINER_NAME} ${BOOTH_HOST_PORT} ${IFRAME_SRC} ${BOOTH_SHOW_RUN_TIME} ${BOOTH_SHOW_COUNT_DOWN} ${OVERLAY_HTML}' \
  <"$WRAPPER_DIR/wrapper.html" >"$SERVE_DIR/index.html"

# Generate nginx config
export OUTER_PORT INNER_PORT API_PORT SERVE_DIR
export BOOTH_VARIANT_TAG="${BOOTH_VARIANT_TAG:-unknown}"
export BOOTH_VERSION_TAG="${BOOTH_VERSION_TAG:-unknown}"
envsubst '${OUTER_PORT} ${INNER_PORT} ${API_PORT} ${SERVE_DIR} ${BOOTH_CONTAINER_NAME} ${BOOTH_VARIANT_TAG} ${BOOTH_VERSION_TAG} ${BOOTH_HOST_PORT}' \
  <"$WRAPPER_DIR/nginx.conf.template" >"$NGINX_CONFIG"

# Propagate SIGTERM to all child processes for clean container shutdown
cleanup() {
    echo "start-booth-wrapped: received signal, shutting down..."
    kill $INNER_PID $NGINX_PID 2>/dev/null
    wait $INNER_PID $NGINX_PID 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# Start the message API server
"$WRAPPER_DIR/booth-message-api-server" "$API_PORT" &

# Start the lifecycle watcher (polls for shutdown/restart marker files)
"$WRAPPER_DIR/booth-lifecycle-watcher" &

# Start the timer notifier (sends toast messages at countdown thresholds)
"$WRAPPER_DIR/booth-timer-notifier" &

# Start the inner service
eval "$INNER_CMD" &
INNER_PID=$!

# Start nginx in background (so we can monitor the inner service)
nginx -c "$NGINX_CONFIG" -g 'daemon off;' &
NGINX_PID=$!

# Wait for the inner service to exit — when it does, shut down the container
wait $INNER_PID
echo "start-booth-wrapped: inner service (PID $INNER_PID) exited, shutting down..."
kill $NGINX_PID 2>/dev/null
wait $NGINX_PID 2>/dev/null
exit 0
STARTEOF
chmod +x /usr/local/bin/start-booth-wrapped

echo "✅ booth-message-wrapper infrastructure installed."
