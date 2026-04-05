#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# booth-message-notebook--setup.sh
#
# Installs:
# 1. A Jupyter server extension with message API endpoints
# 2. An nginx-based wrapper that serves our page at "/" and proxies JupyterLab
# 3. A start-notebook-wrapped launcher that coordinates nginx + JupyterLab
#
# Messages are read from .booth/.tmp/messages/ (same as desktop/codeserver).
# -----------------------------------------------------------------------------

set -euo pipefail

MODULE_DIR="/opt/codingbooth/jupyter-booth-messages"
MODULE_NAME="booth_messages"
WRAPPER_DIR="/usr/local/share/notebook-wrapper"

mkdir -p "${MODULE_DIR}/${MODULE_NAME}"
mkdir -p "${WRAPPER_DIR}"

# ============================================================================
# Part 1: Jupyter server extension (message API)
# ============================================================================

cat > "${MODULE_DIR}/${MODULE_NAME}/__init__.py" <<'PYEOF'
import json
import os
import glob
from datetime import datetime, timezone

from jupyter_server.base.handlers import JupyterHandler
from tornado import web

MSG_DIR = os.path.expanduser("~/code/.booth/.tmp/messages")


class MessageListHandler(JupyterHandler):
    """GET /booth-messages/api/list — return pending messages as JSON."""

    @web.authenticated
    def get(self):
        messages = []
        if os.path.isdir(MSG_DIR):
            for f in sorted(glob.glob(os.path.join(MSG_DIR, "*.msg.json"))):
                msg_id = os.path.basename(f).replace(".msg.json", "")
                resp_file = os.path.join(MSG_DIR, msg_id + ".response.json")
                if os.path.exists(resp_file):
                    continue
                try:
                    with open(f) as fh:
                        msg = json.load(fh)
                    if msg.get("expires"):
                        exp = datetime.fromisoformat(msg["expires"].replace("Z", "+00:00"))
                        if datetime.now(timezone.utc) > exp:
                            _write_response(msg_id, "timeout")
                            continue
                    messages.append(msg)
                except Exception:
                    continue
        self.set_header("Content-Type", "application/json")
        self.finish(json.dumps(messages))


class MessageRespondHandler(JupyterHandler):
    """POST /booth-messages/api/respond/<msg_id> — write response."""

    @web.authenticated
    def post(self, msg_id):
        try:
            body = json.loads(self.request.body)
            answer = body.get("answer", "")
        except Exception:
            self.set_status(400)
            self.finish(json.dumps({"error": "Invalid JSON body"}))
            return
        _write_response(msg_id, answer)
        self.set_header("Content-Type", "application/json")
        self.finish(json.dumps({"ok": True}))


class WrapperPageHandler(JupyterHandler):
    """GET /booth — wrapper page served by Jupyter (sets XSRF cookie)."""

    @web.authenticated
    def get(self):
        self.set_header("Content-Type", "text/html")
        self.finish(WRAPPER_HTML)


def _write_response(msg_id, answer):
    os.makedirs(MSG_DIR, exist_ok=True)
    resp = {
        "id": msg_id,
        "answer": answer,
        "answered": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    resp_file = os.path.join(MSG_DIR, msg_id + ".response.json")
    with open(resp_file, "w") as fh:
        json.dump(resp, fh, indent=2)


WRAPPER_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CodingBooth Notebook</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; overflow: hidden; background: #111; }
  iframe#lab { width: 100%; height: 100%; border: none; }

  .overlay {
    display: none;
    position: fixed; top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0,0,0,0.5);
    z-index: 10000;
    justify-content: center; align-items: center;
  }
  .overlay.visible { display: flex; }

  .dialog-stack {
    display: flex; flex-direction: column; gap: 12px;
    max-height: 80vh; overflow-y: auto; padding: 20px;
    width: 100%; max-width: 480px;
  }
  .dialog {
    background: #fff; border-radius: 10px; padding: 20px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.3);
    font-family: -apple-system, "Segoe UI", sans-serif;
  }
  .dialog h2 { font-size: 15px; color: #333; margin-bottom: 6px; }
  .dialog p { font-size: 14px; color: #555; margin-bottom: 14px; }
  .actions { display: flex; gap: 8px; }
  button {
    padding: 7px 18px; border-radius: 6px; border: 1px solid #ccc;
    cursor: pointer; font-size: 13px; font-weight: 500;
  }
  .btn-yes { background: #2563eb; color: #fff; border-color: #2563eb; }
  .btn-yes:hover { background: #1d4ed8; }
  .btn-no { background: #f3f4f6; }
  .btn-no:hover { background: #e5e7eb; }
  input[type=text] {
    padding: 7px 10px; border: 1px solid #ccc; border-radius: 6px;
    flex: 1; font-size: 13px;
  }
  .btn-submit { background: #2563eb; color: #fff; border-color: #2563eb; }
</style>
</head>
<body>

<iframe id="lab" src="/lab"></iframe>

<div class="overlay" id="overlay">
  <div class="dialog-stack" id="dialogs"></div>
</div>

<script>
var overlay = document.getElementById("overlay");
var dialogs = document.getElementById("dialogs");

function getCookie(name) {
  var m = document.cookie.match(new RegExp("(?:^|; )" + name + "=([^;]*)"));
  return m ? decodeURIComponent(m[1]) : "";
}

function esc(s) {
  var d = document.createElement("div");
  d.textContent = s;
  return d.innerHTML;
}

function poll() {
  fetch("/booth-messages/api/list").then(function(resp) {
    if (!resp.ok) return;
    return resp.json();
  }).then(function(msgs) {
    if (!msgs || !msgs.length) {
      overlay.classList.remove("visible");
      dialogs.innerHTML = "";
      return;
    }
    overlay.classList.add("visible");
    dialogs.innerHTML = msgs.map(function(m) {
      if (m.type === "text") {
        return '<div class="dialog"><h2>' + esc(m.title) + '</h2><p>' + esc(m.body) + '</p>' +
          '<form class="actions" onsubmit="respond(\'' + m.id + '\', this.answer.value); return false;">' +
            '<input type="text" name="answer" placeholder="Type response..." autofocus>' +
            '<button type="submit" class="btn-submit">Send</button>' +
          '</form></div>';
      }
      return '<div class="dialog"><h2>' + esc(m.title) + '</h2><p>' + esc(m.body) + '</p>' +
        '<div class="actions">' +
          '<button class="btn-yes" onclick="respond(\'' + m.id + '\',\'yes\')">Yes</button>' +
          '<button class="btn-no" onclick="respond(\'' + m.id + '\',\'no\')">No</button>' +
        '</div></div>';
    }).join("");
  }).catch(function() {});
}

function respond(id, answer) {
  fetch("/booth-messages/api/respond/" + id, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-XSRFToken": getCookie("_xsrf")
    },
    body: JSON.stringify({answer: answer})
  }).then(function() { poll(); });
}

poll();
setInterval(poll, 2000);
</script>
</body>
</html>
"""


def _load_jupyter_server_extension(server_app):
    """Register message API and wrapper page handlers."""
    web_app = server_app.web_app
    host_pattern = ".*$"
    base_url = web_app.settings["base_url"]

    web_app.add_handlers(host_pattern, [
        (base_url + r"booth-messages/api/list", MessageListHandler),
        (base_url + r"booth-messages/api/respond/(.+)", MessageRespondHandler),
        (base_url + r"booth/?", WrapperPageHandler),
    ])
    server_app.log.info("booth-messages extension loaded (wrapper at %sbooth)", base_url)
PYEOF

cat > "${MODULE_DIR}/setup.py" <<'SETUP'
from setuptools import setup, find_packages
setup(
    name="booth-messages",
    version="1.0.0",
    packages=find_packages(),
    install_requires=["jupyter_server>=2"],
)
SETUP

# Install into the notebook venv
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
pip install -e "${MODULE_DIR}" --no-deps 2>/dev/null || pip install -e "${MODULE_DIR}"

# Enable via config file
JUPYTER_CONFIG_DIR="/etc/jupyter"
mkdir -p "${JUPYTER_CONFIG_DIR}"
CONF_FILE="${JUPYTER_CONFIG_DIR}/jupyter_server_config.json"
if [ -f "$CONF_FILE" ]; then
  python3 -c "
import json
with open('$CONF_FILE') as f:
    cfg = json.load(f)
sa = cfg.setdefault('ServerApp', {})
sa.setdefault('jpserver_extensions', {})['booth_messages'] = True
with open('$CONF_FILE', 'w') as f:
    json.dump(cfg, f, indent=2)
"
else
  cat > "$CONF_FILE" <<'CONFJSON'
{
  "ServerApp": {
    "jpserver_extensions": {
      "booth_messages": true
    }
  }
}
CONFJSON
fi

# ============================================================================
# Part 2: nginx config template
# ============================================================================

cat > "${WRAPPER_DIR}/nginx.conf.template" <<'NGINXEOF'
worker_processes auto;
pid /tmp/nginx-notebook.pid;
error_log /tmp/nginx-notebook-error.log warn;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /tmp/nginx-notebook-access.log;
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

    server {
        listen ${PORT};
        server_name _;
        absolute_redirect off;

        # Redirect root to our wrapper page
        location = / {
            return 302 /booth;
        }

        # Proxy everything to JupyterLab (including /booth, /lab, /api, etc.)
        location / {
            proxy_pass http://127.0.0.1:${JUPYTER_PORT};
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

# ============================================================================
# Part 3: Wrapper start script
# ============================================================================

cat > /usr/local/bin/start-notebook-wrapped <<'STARTEOF'
#!/usr/bin/env bash
set -euo pipefail

# Ports
PORT=${BOOTH_CODE_PORT:-10000}
JUPYTER_PORT=18888
WRAPPER_ROOT=/usr/local/share/notebook-wrapper
NGINX_CONFIG=/tmp/nginx-notebook.conf

# Generate nginx config
export PORT JUPYTER_PORT
envsubst '${PORT} ${JUPYTER_PORT}' \
  <"$WRAPPER_ROOT/nginx.conf.template" >"$NGINX_CONFIG"

mkdir -p /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi

# Start JupyterLab on internal port (background)
# Override BOOTH_CODE_PORT so start-notebook uses our internal port
BOOTH_CODE_PORT=$JUPYTER_PORT start-notebook "$JUPYTER_PORT" &

# Start nginx in foreground
exec nginx -c "$NGINX_CONFIG" -g 'daemon off;'
STARTEOF
chmod +x /usr/local/bin/start-notebook-wrapped

echo "✅ booth-messages notebook wrapper installed."
echo "   nginx serves wrapper at /, proxies JupyterLab at /lab"
