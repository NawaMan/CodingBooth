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
# Drop-in directory for lifecycle-panel plugins (per-variant or per-environment
# setup scripts can write `*.js` files here; start-booth-wrapped concatenates
# them into the wrapper HTML so `BoothPanel.register(...)` calls become live).
mkdir -p "${WRAPPER_DIR}/plugins"

# ── Copy the shared overlay HTML ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "${SCRIPT_DIR}/booth-message-overlay.html" "${WRAPPER_DIR}/overlay.html"
cp "${SCRIPT_DIR}/booth-ready.js" "${WRAPPER_DIR}/booth-ready.js"
cp "${SCRIPT_DIR}/booth-keyboard-capture.js" "${WRAPPER_DIR}/booth-keyboard-capture.js"
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
${BOOTH_READY_JS}
${BOOTH_KEYBOARD_CAPTURE_JS}
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; overflow: hidden; background: #111; }
  iframe#booth-inner { width: 100%; height: 100%; border: none; }
</style>
</head>
<body>
<iframe id="booth-inner" data-booth-src="${IFRAME_SRC}" allow="clipboard-read; clipboard-write"></iframe>
<script>
// The frame is loaded by the readiness gate, not by the markup: nginx answers
// on this port before the inner service does, so a frame that loads with the
// page shows nginx's 502. This also re-runs whenever the booth comes back, so a
// booth--restart reloads the frame instead of leaving the error page behind.
// See booth-ready.js.
(function () {
  var inner = document.getElementById("booth-inner");
  window.BoothReady.onUp(function () {
    inner.src = inner.dataset.boothSrc;
  });
})();
// Fit the desktop to the browser. noVNC's resize=remote asks the VNC server to
// do this, and TigerVNC (X11 desktops) does; wayvnc 0.7 (the Wayland desktop)
// ignores it. So report the frame's size to the booth, which resizes the
// desktop itself when it can — whenever the booth comes up and on every window
// resize (Full screen included). A booth without a resize hook answers
// supported:false, and the page stops asking.
(function () {
  var inner = document.getElementById("booth-inner");
  var supported = true, last = "", timer = null;
  function report() {
    var w = inner.clientWidth, h = inner.clientHeight, key = w + "x" + h;
    if (!supported || !w || !h || key === last) return;
    last = key;
    fetch("/booth-messages/api/display-size", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ width: w, height: h })
    }).then(function (r) { return r.json(); })
      .then(function (j) {
        if (j && j.supported === false) supported = false;
        else if (!j || !j.ok) last = "";   // not up yet: try again next time
      })
      .catch(function () { last = ""; });
  }
  function schedule(delay) {
    clearTimeout(timer);
    timer = setTimeout(report, delay);
  }
  window.addEventListener("resize", function () { schedule(400); });
  window.BoothReady.onUp(function () {
    last = "";
    schedule(0);
    // The desktop may still be starting when the booth first answers.
    setTimeout(function () { last = ""; schedule(0); }, 5000);
  });
})();
window.BOOTH_SHOW_RUN_TIME="${BOOTH_SHOW_RUN_TIME}";
window.BOOTH_SHOW_COUNT_DOWN="${BOOTH_SHOW_COUNT_DOWN}";
window.BOOTH_IDLE_TIME="${BOOTH_IDLE_TIME}";
window.BOOTH_IDLE_SHUTDOWN_TIME="${BOOTH_IDLE_SHUTDOWN_TIME}";
</script>
${OVERLAY_HTML}
${PLUGINS_HTML}
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

    # Compresses nginx's own responses to the browser. Paired with the
    # catch-all location's `proxy_set_header Accept-Encoding ""` below: that
    # asks the *inner service* for an uncompressed body (so sub_filter can
    # read it), and this recovers the bandwidth on the client-facing leg
    # instead of just giving it up — relevant for a heavier inner service
    # like JupyterLab or code-server's own JS bundles.
    gzip on;
    gzip_vary on;
    gzip_types text/css application/javascript application/json image/svg+xml;

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

    # http-level half of a variant's Web Preview (e.g. notebook's cookie maps);
    # empty unless the variant names one.
    ${WRAPPER_PREVIEW_HTTP}

    server {
        listen ${OUTER_PORT};
        server_name _;
        absolute_redirect off;

        # Only the code-server and notebook variants enable these locations, and
        # both authenticate every preview request against the inner service
        # before any application content reaches the browser.
        ${WRAPPER_PREVIEW_LOCATIONS}

        # Wrapper page
        location = /booth {
            alias ${SERVE_DIR}/index.html;
            default_type text/html;
        }

        # Booth liveness — proxies to inner service; 2xx/3xx/4xx → 200, 5xx/timeout → unhealthy.
        location = /__booth/health {
            access_log off;
            # Which booth is answering — see the page's readiness gate. Ports get
            # reused, so a tab left open from a booth that has since been
            # replaced needs to notice it is driving a stranger. `always` so the
            # id rides the 502 as well.
            add_header X-Booth-Instance "${BOOTH_INSTANCE_ID}" always;
            # WRAPPER_HEALTH_PATH ("/" unless the variant names a quieter one:
            # this is polled every few seconds by every open page).
            proxy_pass http://127.0.0.1:${INNER_PORT}${WRAPPER_HEALTH_PATH};
            proxy_connect_timeout 2s;
            proxy_read_timeout 3s;
            proxy_intercept_errors on;
            error_page 301 302 303 304 307 308 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 422 429 =200 @__booth_alive;
        }
        location @__booth_alive {
            internal;
            default_type text/plain;
            add_header Cache-Control "no-store" always;
            # add_header does not inherit into a named location that sets any of
            # its own, so the instance id is repeated rather than shared.
            add_header X-Booth-Instance "${BOOTH_INSTANCE_ID}" always;
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

        # Silence JupyterLab's service-worker polling. JupyterLab tries to
        # fetch /_static/out/browser/serviceWorker.js from the wrapper root
        # every couple of seconds; the file does not exist (JupyterLab is
        # only mounted under /lab here), so every poll would otherwise 404
        # inside the inner Jupyter and flood the container logs. A 204 with
        # no body is what the browser treats as "nothing to update here".
        location = /_static/out/browser/serviceWorker.js {
            access_log off;
            return 204;
        }

        # Fira Code Nerd Font Mono, served as a real cacheable asset. Always
        # present — every base-derived image installs it unconditionally
        # (fira-code-nerd-font--setup.sh) — so this is safe to expose
        # regardless of which inner service a given variant wraps.
        location /booth-assets/fonts/ {
            alias /usr/share/fonts/truetype/fira-code-nerd-font/;
            add_header Cache-Control "public, max-age=31536000, immutable";
        }

        # Root — redirect to /booth unless _booth_inner is set
        location = / {
            # sub_filter cannot rewrite a compressed body, and a real browser
            # (unlike curl) sends Accept-Encoding: gzip by default. Scoped to
            # this exact-match root document only — the catch-all below still
            # serves the inner service's JS/CSS bundles gzip'd, so a heavier
            # app like code-server doesn't pay for this on its whole payload.
            proxy_set_header Accept-Encoding "";
            sub_filter_once on;
            # WRAPPER_HEAD_INJECT is opt-in and empty by default (see
            # start-booth-wrapped) — a no-op for every wrapped service that
            # doesn't set it.
            sub_filter '<head>' '<head>${WRAPPER_HEAD_INJECT}';

            if ($root_action = "proxy") {
                proxy_pass http://127.0.0.1:${INNER_PORT};
                break;
            }
            return 302 /booth;
        }

        # Everything else — proxy to the inner service. Unlike the exact `/`
        # above, an inner service can serve its real UI shell (and reachable
        # sub-pages of it, e.g. JupyterLab's /lab, /lab/tree/...) from more
        # than just the bare root, so the same injection has to reach here
        # too. sub_filter_types defaults to text/html only, so this is a
        # no-op against JS/CSS/asset responses passing through the same
        # location — only an actual HTML document gets the sub_filter cost.
        location / {
            proxy_pass http://127.0.0.1:${INNER_PORT};
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Accept-Encoding "";
            proxy_read_timeout 24h;
            proxy_buffering off;

            sub_filter_once on;
            sub_filter '<head>' '<head>${WRAPPER_HEAD_INJECT}';
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
export BOOTH_IDLE_TIME="${BOOTH_IDLE_TIME:-0}"
export BOOTH_IDLE_SHUTDOWN_TIME="${BOOTH_IDLE_SHUTDOWN_TIME:-60}"
OVERLAY_HTML=$(cat "$WRAPPER_DIR/overlay.html")
export OVERLAY_HTML

# Identity for this container start. A booth is reached by port, and ports get
# reused: stop one booth, start another on the same port, and a browser tab left
# open from the first still shows its page. The page carries this id and the
# readiness gate reloads the page when the booth answering stops matching it.
# Regenerated per start, so a restart counts as a new instance too.
BOOTH_INSTANCE_ID=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
export BOOTH_INSTANCE_ID

# The readiness gate goes in <head>, so it is already polling before the frame
# it gates is parsed. The instance id is declared just ahead of it, in its own
# script, so the gate can read it on its very first probe.
BOOTH_READY_JS="<script>window.BOOTH_INSTANCE_ID=\"${BOOTH_INSTANCE_ID}\";</script>
<script>
$(cat "$WRAPPER_DIR/booth-ready.js")
</script>"
export BOOTH_READY_JS

# Feature-detected fullscreen + Keyboard Lock toggle behind the overlay's
# "Full screen" button — see booth-keyboard-capture.js for why this
# can't just be a preventDefault() in the wrapped service's own key handlers.
BOOTH_KEYBOARD_CAPTURE_JS="<script>
$(cat "$WRAPPER_DIR/booth-keyboard-capture.js")
</script>"
export BOOTH_KEYBOARD_CAPTURE_JS

# Concatenate any lifecycle-panel plugin scripts into the wrapper HTML. Each
# file is wrapped in its own <script> tag so a parse error in one doesn't
# poison the others. Runs after overlay.html so window.BoothPanel is defined.
PLUGINS_HTML=""
if ls "$WRAPPER_DIR/plugins"/*.js >/dev/null 2>&1; then
  for plugin_file in "$WRAPPER_DIR/plugins"/*.js; do
    PLUGINS_HTML="${PLUGINS_HTML}
<!-- booth plugin: $(basename "$plugin_file") -->
<script>
$(cat "$plugin_file")
</script>"
  done
fi
export PLUGINS_HTML

envsubst '${BOOTH_CONTAINER_NAME} ${BOOTH_HOST_PORT} ${IFRAME_SRC} ${BOOTH_SHOW_RUN_TIME} ${BOOTH_SHOW_COUNT_DOWN} ${BOOTH_IDLE_TIME} ${BOOTH_IDLE_SHUTDOWN_TIME} ${OVERLAY_HTML} ${PLUGINS_HTML} ${BOOTH_READY_JS} ${BOOTH_KEYBOARD_CAPTURE_JS}' \
  <"$WRAPPER_DIR/wrapper.html" >"$SERVE_DIR/index.html"

# Generate nginx config
export OUTER_PORT INNER_PORT API_PORT SERVE_DIR
export BOOTH_VARIANT_TAG="${BOOTH_VARIANT_TAG:-unknown}"
export BOOTH_VERSION_TAG="${BOOTH_VERSION_TAG:-unknown}"
# Opt-in HTML a variant's start-*-wrapped script wants injected into the
# inner service's root <head> (e.g. an @font-face style) — empty by default,
# a no-op sub_filter for every wrapped service that doesn't set it.
export WRAPPER_HEAD_INJECT="${WRAPPER_HEAD_INJECT:-}"
# Path /__booth/health probes on the inner service. Any 2xx-4xx answer counts
# as up, so a variant can point this at an endpoint its service does not log.
export WRAPPER_HEALTH_PATH="${WRAPPER_HEALTH_PATH:-/}"
# Web Preview: the server-block locations come from WRAPPER_PREVIEW_TEMPLATE
# (code-server's, forwarding /proxy/ to its own authenticated path proxy, by
# default) and an optional http-block part from WRAPPER_PREVIEW_HTTP_TEMPLATE.
export WRAPPER_PREVIEW_LOCATIONS=""
export WRAPPER_PREVIEW_HTTP=""
if [[ "${BOOTH_WEB_PREVIEW:-0}" == 1 ]]; then
  WRAPPER_PREVIEW_LOCATIONS=$(envsubst '${INNER_PORT}' \
    <"${WRAPPER_PREVIEW_TEMPLATE:-/usr/local/share/booth-web-preview/nginx.conf.template}")
  if [[ -n "${WRAPPER_PREVIEW_HTTP_TEMPLATE:-}" ]]; then
    WRAPPER_PREVIEW_HTTP=$(cat "$WRAPPER_PREVIEW_HTTP_TEMPLATE")
  fi
fi
envsubst '${OUTER_PORT} ${INNER_PORT} ${API_PORT} ${SERVE_DIR} ${BOOTH_CONTAINER_NAME} ${BOOTH_VARIANT_TAG} ${BOOTH_VERSION_TAG} ${BOOTH_HOST_PORT} ${BOOTH_INSTANCE_ID} ${WRAPPER_HEAD_INJECT} ${WRAPPER_PREVIEW_LOCATIONS} ${WRAPPER_PREVIEW_HTTP} ${WRAPPER_HEALTH_PATH}' \
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
