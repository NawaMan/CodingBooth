#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Creates start-notebook-wrapped: nginx wrapper around JupyterLab.
# Also installs the Jupyter server extension for the message API
# (Jupyter-served endpoints handle XSRF properly).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="/opt/codingbooth/jupyter-booth-messages"
MODULE_NAME="booth_messages"

mkdir -p "${MODULE_DIR}/${MODULE_NAME}"

# ── Jupyter server extension (message API only) ──
cat > "${MODULE_DIR}/${MODULE_NAME}/__init__.py" <<'PYEOF'
import json
import os
import glob
from datetime import datetime, timezone

from jupyter_server.base.handlers import JupyterHandler
from tornado import web

MSG_DIR = "/home/coder/code/.booth/.tmp/messages"


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


def _load_jupyter_server_extension(server_app):
    """Register message API handlers."""
    web_app = server_app.web_app
    host_pattern = ".*$"
    base_url = web_app.settings["base_url"]

    web_app.add_handlers(host_pattern, [
        (base_url + r"booth-messages/api/list", MessageListHandler),
        (base_url + r"booth-messages/api/respond/(.+)", MessageRespondHandler),
    ])
    server_app.log.info("booth-messages API loaded")
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

# ── Create start-notebook-wrapped ──
# For notebook, the message API is served by Jupyter (XSRF-aware),
# so we tell the wrapper to proxy /booth-messages through Jupyter
# instead of using the bash API server.
cat > /usr/local/bin/start-notebook-wrapped <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=18888
export INNER_CMD="BOOTH_CODE_PORT=18888 start-notebook 18888"
export IFRAME_SRC="/lab"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-notebook-wrapped

echo "✅ start-notebook-wrapped + Jupyter message extension installed."
