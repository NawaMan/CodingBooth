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
  PORT  Port for the Hoppscotch web UI (default: 13000)

Examples:
  $0           # install with default port 13000
  $0 18000     # use port 18000

Prerequisites:
- Hoppscotch frontend must be pre-installed at /opt/hoppscotch
  (typically via COPY --from=hoppscotch/hoppscotch-frontend:<version>
   /site/selfhost-web /opt/hoppscotch)

Notes:
- Creates a starter script at /usr/local/bin/start-hoppscotch
- Serves the SPA plus a same-origin CORS proxy (Proxyscotch protocol)
- Hoppscotch web UI is accessible at http://localhost:<PORT>
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
HOPPSCOTCH_PORT="${1:-13000}"
HOPPSCOTCH_DIR="/opt/hoppscotch"
PROFILE_FILE="/etc/profile.d/70-cb-hoppscotch--profile.sh"
STARTER_FILE="/usr/local/bin/start-hoppscotch"
SERVER_FILE="/usr/local/bin/hoppscotch-server"

# ---- verify frontend is present ----
if [[ ! -f "$HOPPSCOTCH_DIR/index.html" ]]; then
  echo "❌ Hoppscotch frontend not found at $HOPPSCOTCH_DIR"
  echo "   Use COPY --from=hoppscotch/hoppscotch-frontend:<version> /site/selfhost-web /opt/hoppscotch"
  exit 1
fi

# ---- python3 for the SPA + CORS-proxy server ----
if command -v python3 >/dev/null 2>&1; then
  echo "• Python already installed: $(python3 --version 2>&1)"
else
  echo "• Installing python3 ..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends python3
  rm -rf /var/lib/apt/lists/*
fi

# ---- runtime env in index.html (relative URLs so +expose / booth proxy work) ----
python3 - "$HOPPSCOTCH_DIR/index.html" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
env = {
    "VITE_BASE_URL": "",
    "VITE_BACKEND_GQL_URL": "/graphql",
    "VITE_BACKEND_WS_URL": "",
    "VITE_BACKEND_API_URL": "/v1",
    "VITE_SHORTCODE_BASE_URL": "",
    "VITE_PROXYSCOTCH_ACCESS_TOKEN": "",
    "VITE_APP_TOS_LINK": "https://docs.hoppscotch.io/support/terms",
    "VITE_APP_PRIVACY_POLICY_LINK": "https://docs.hoppscotch.io/support/privacy",
}
old = """globalThis.import_meta_env = JSON.parse('"import_meta_env_placeholder"')"""
new = "globalThis.import_meta_env = " + json.dumps(env, separators=(",", ":"))
if old not in text:
    sys.exit("hoppscotch--setup: import_meta_env placeholder not found in index.html")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

# Point the baked-in interceptor at the same-origin proxy (no backend, no hoppscotch.io).
# Filenames are hashed per release; replace across the bundle so a version bump still matches.
echo "• Defaulting interceptor to the local CORS proxy ..."
find "$HOPPSCOTCH_DIR" -type f -name '*.js' -print0 \
  | xargs -0 sed -i \
    -e 's/defaultInterceptor:"browser"/defaultInterceptor:"proxy"/g' \
    -e 's|https://proxy.hoppscotch.io/|/proxy|g' \
    -e 's|https://proxy.hoppscotch.io|/proxy|g'

chmod -R a+rX "$HOPPSCOTCH_DIR"

# ---- SPA + Proxyscotch-protocol CORS proxy (stdlib only) ----
cat > "${SERVER_FILE}" <<'PY'
#!/usr/bin/env python3
"""Serve Hoppscotch and a same-origin Proxyscotch-compatible CORS proxy."""
from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import posixpath
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
    "host",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    root = Path("/opt/hoppscotch")

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Expose-Headers", "*")

    def _send(self, status: int, body: bytes, content_type: str, extra: dict[str, str] | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_json(self, status: int, payload: object) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self._send(status, raw, "application/json; charset=utf-8")

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return b""
        return self.rfile.read(length)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_HEAD(self) -> None:  # noqa: N802
        self.do_GET()

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith("/graphql"):
            self._send_json(200, {"errors": [{"message": "auth/cookies_not_found"}]})
            return
        if self.path.startswith("/v1"):
            self._send_json(200, {})
            return
        self._serve_static()

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in ("/proxy", "/proxy/"):
            self._proxy()
            return
        if path.startswith("/graphql"):
            self._send_json(200, {"errors": [{"message": "auth/cookies_not_found"}]})
            return
        if path.startswith("/v1"):
            self._send_json(200, {})
            return
        self._send_json(404, {"error": "not found"})

    def do_PUT(self) -> None:  # noqa: N802
        self.do_POST()

    def do_PATCH(self) -> None:  # noqa: N802
        self.do_POST()

    def do_DELETE(self) -> None:  # noqa: N802
        self.do_POST()

    def _serve_static(self) -> None:
        raw = urllib.parse.unquote(self.path.split("?", 1)[0])
        rel = posixpath.normpath(raw.lstrip("/"))
        if rel == ".":
            rel = "index.html"
        root = self.root.resolve()
        candidate = (self.root / rel).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            self._send(403, b"forbidden", "text/plain")
            return
        if candidate.is_dir():
            candidate = candidate / "index.html"
        if not candidate.is_file():
            candidate = self.root / "index.html"
        data = candidate.read_bytes()
        ctype = mimetypes.guess_type(str(candidate))[0] or "application/octet-stream"
        if candidate.name == "index.html":
            ctype = "text/html; charset=utf-8"
        self._send(200, data, ctype)

    def _proxy(self) -> None:
        try:
            req = json.loads(self._read_body().decode("utf-8") or "{}")
        except json.JSONDecodeError as exc:
            self._send_json(400, {"success": False, "isBinary": False, "status": 0,
                                  "statusText": str(exc), "headers": {}, "data": ""})
            return

        url = req.get("url") or ""
        method = (req.get("method") or "GET").upper()
        headers = {str(k): str(v) for k, v in (req.get("headers") or {}).items()}
        params = req.get("params") or {}
        data = req.get("data")
        auth = req.get("auth") or {}

        if params:
            parsed = urllib.parse.urlsplit(url)
            q = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
            q.update({str(k): str(v) for k, v in params.items()})
            url = urllib.parse.urlunsplit(
                (parsed.scheme, parsed.netloc, parsed.path,
                 urllib.parse.urlencode(q), parsed.fragment)
            )

        if auth.get("username") is not None:
            token = base64.b64encode(
                f"{auth.get('username', '')}:{auth.get('password', '')}".encode()
            ).decode("ascii")
            headers.setdefault("Authorization", "Basic " + token)

        body: bytes | None = None
        if data not in (None, ""):
            body = data.encode("utf-8") if isinstance(data, str) else bytes(data)

        cleaned = {k: v for k, v in headers.items() if k.lower() not in HOP_BY_HOP}
        request = urllib.request.Request(url, data=body, method=method, headers=cleaned)
        ctx = ssl.create_default_context()
        try:
            with urllib.request.urlopen(request, timeout=30, context=ctx) as resp:
                raw = resp.read()
                status = getattr(resp, "status", 200)
                reason = getattr(resp, "reason", "OK") or "OK"
                out_headers = {k: v for k, v in resp.headers.items()}
        except urllib.error.HTTPError as exc:
            raw = exc.read() or b""
            status = exc.code
            reason = exc.reason or "Error"
            out_headers = {k: v for k, v in (exc.headers.items() if exc.headers else [])}
        except Exception as exc:  # noqa: BLE001 — surface any fetch failure to the UI
            self._send_json(200, {
                "success": False,
                "isBinary": False,
                "status": 0,
                "statusText": str(exc),
                "headers": {},
                "data": "",
            })
            return

        self._send_json(200, {
            "success": True,
            "isBinary": True,
            "status": int(status),
            "statusText": str(reason),
            "headers": out_headers,
            "data": base64.b64encode(raw).decode("ascii"),
        })


def main() -> int:
    parser = argparse.ArgumentParser(description="Hoppscotch SPA + CORS proxy")
    parser.add_argument("--port", type=int, default=13000)
    parser.add_argument("--root", default="/opt/hoppscotch")
    args = parser.parse_args()
    Handler.root = Path(args.root)
    if not (Handler.root / "index.html").is_file():
        print(f"❌ Hoppscotch frontend not found at {Handler.root}", file=sys.stderr)
        return 1
    httpd = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"Hoppscotch listening on http://0.0.0.0:{args.port}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod 755 "${SERVER_FILE}"

# ---- starter (foreground; +autostart nohups this) ----
cat > "${STARTER_FILE}" <<STARTER
#!/usr/bin/env bash
set -euo pipefail

PORT=\${1:-${HOPPSCOTCH_PORT}}

echo "Starting Hoppscotch on http://localhost:\$PORT ..."
exec ${SERVER_FILE} --port "\$PORT" --root ${HOPPSCOTCH_DIR}
STARTER
chmod 755 "${STARTER_FILE}"

# ---- profile ----
cat > "${PROFILE_FILE}" <<PROFILE
# Hoppscotch environment
export HOPPSCOTCH_HOME="${HOPPSCOTCH_DIR}"
export HOPPSCOTCH_PORT="${HOPPSCOTCH_PORT}"

hoppscotch--info() {
  echo "Hoppscotch"
  echo "  Home:    ${HOPPSCOTCH_DIR}"
  echo "  Port:    ${HOPPSCOTCH_PORT}"
  echo "  Starter: ${STARTER_FILE}"
  echo "  URL:     http://localhost:${HOPPSCOTCH_PORT}"
}
PROFILE
chmod 644 "${PROFILE_FILE}"

# ---- desktop icon (no-op off-desktop) ----
ICON="applications-internet"
for candidate in logo.svg icon.png favicon.ico; do
  if [[ -f "$HOPPSCOTCH_DIR/$candidate" ]]; then
    ICON="$HOPPSCOTCH_DIR/$candidate"
    break
  fi
done
cb-web-icon.sh --id hoppscotch --name "Hoppscotch" --icon "$ICON" \
  --port-env HOPPSCOTCH_PORT --port "${HOPPSCOTCH_PORT}" \
  --path / --start start-hoppscotch

echo ""
echo "✅ Hoppscotch setup complete."
echo "   Location:  ${HOPPSCOTCH_DIR}"
echo "   Port:      ${HOPPSCOTCH_PORT}"
echo "   Starter:   ${STARTER_FILE}"
echo ""
echo "ℹ️  Ready to use:"
echo "   start-hoppscotch [PORT]"
echo "   Access: http://localhost:${HOPPSCOTCH_PORT}"
echo "   REST/GraphQL tester with a same-origin CORS proxy (Interceptor: Proxy)."
echo "   Collections stay in the browser (localStorage); no Hoppscotch backend."
