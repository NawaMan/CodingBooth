#!/bin/bash
# cloudflared-share puts this booth's site on a public trycloudflare.com URL, and
# that URL really serves the page (fetched back over the internet). It refuses
# the booth's own port unless told --ok-booth.
set -euo pipefail
source "$(dirname "$0")/share-lib.sh"

echo "=== cloudflared is installed ==="
cloudflared --version

echo "=== refuses the booth's own port (10000) ==="
if out="$(cloudflared-share 10000 2>&1)"; then fail "cloudflared-share 10000 should be refused"; fi
echo "$out" | grep -q -- '--ok-booth' || fail "refusal does not mention --ok-booth: $out"
echo "ok"

echo "=== shares the site on a public URL ==="
start_site
cloudflared-share "$PORT" >"$LOG_DIR/share.log" 2>&1 &
PIDS+=($!)
url="$(wait_for_url "$LOG_DIR/share.log")" || fail "no Shared: URL from cloudflared-share"
echo "URL: $url"
[[ "$url" == https://*.trycloudflare.com ]] || fail "unexpected URL: $url"
fetch_marker "$url" || fail "$url does not serve the site"
echo "ok: the public URL serves the booth's page"
