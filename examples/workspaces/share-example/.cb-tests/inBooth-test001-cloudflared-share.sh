#!/bin/bash
# The dev workflow with Cloudflare: `just dev` runs the API and the front end,
# `just share-web` gives the whole app a public URL (page + API through its
# proxy), `just share-api` gives the API its own. Each public URL is fetched
# back over the internet. The booth's own port is refused without --ok-booth.
set -euo pipefail
source "$(dirname "$0")/share-lib.sh"

echo "=== cloudflared is installed ==="
cloudflared --version

echo "=== refuses the booth's own port (10000) ==="
if out="$(cloudflared-share 10000 2>&1)"; then fail "cloudflared-share 10000 should be refused"; fi
echo "$out" | grep -q -- '--ok-booth' || fail "refusal does not mention --ok-booth: $out"
echo "ok"

echo "=== the app runs locally (dev.sh) ==="
start_app
curl -fsS "http://localhost:$WEB_PORT/" | grep -q 'share-example app' || fail "front end does not serve the page"
curl -fsS -X POST -H 'Content-Type: application/json' -d '{"text":"hello from test001","author":"test"}' \
    "http://localhost:$WEB_PORT/api/notes" | grep -q 'hello from test001' || fail "POST through the front end's /api proxy failed"
echo "ok"

echo "=== share-web: the whole app on a public URL ==="
web_url="$(share cloudflared-share "$WEB_PORT")" || fail "no Shared: URL for the front end"
echo "URL: $web_url"
[[ "$web_url" == https://*.trycloudflare.com ]] || fail "unexpected URL: $web_url"
fetch_until "$web_url/" 'share-example app' || fail "$web_url does not serve the page"
fetch_until "$web_url/api/notes" 'hello from test001' || fail "$web_url/api/notes does not reach the API"
echo "ok: page and API reachable through the front end's public URL"

echo "=== share-api: the API on its own public URL ==="
api_url="$(share cloudflared-share "$API_PORT")" || fail "no Shared: URL for the API"
echo "URL: $api_url"
fetch_until "$api_url/api/health" '"service":"notes-api"' || fail "$api_url/api/health does not answer"
echo "ok: API reachable on its own public URL"
