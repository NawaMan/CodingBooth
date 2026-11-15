#!/bin/bash
# Serve ./site on port 8080 in the booth and share it on a public URL.
#   ./share.sh cloudflared   # Cloudflare quick tunnel, no account
#   ./share.sh ngrok         # ngrok, needs NGROK_AUTHTOKEN
# Ctrl+C stops both the tunnel and the server.
set -euo pipefail
cd "$(dirname "$0")"

VIA="${1:-cloudflared}"
PORT="${PORT:-8080}"
case "$VIA" in
    cloudflared|ngrok) ;;
    *) echo "usage: $0 cloudflared|ngrok" >&2; exit 2 ;;
esac

if curl -fsS -o /dev/null "http://localhost:$PORT/" 2>/dev/null; then
    echo "Port $PORT already answers; sharing what is there."
else
    caddy file-server --listen ":$PORT" --root site >/tmp/share-example-caddy.log 2>&1 &
    SERVER_PID=$!
    trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
    for _ in $(seq 1 50); do
        curl -fsS -o /dev/null "http://localhost:$PORT/" 2>/dev/null && break
        sleep 0.1
    done
fi

"$VIA-share" "$PORT"
