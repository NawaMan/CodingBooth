#!/bin/bash
# ngrok-share: without an authtoken it says how to get one; it refuses the booth's
# own port; with NGROK_AUTHTOKEN set it shares the site and the URL serves it.
set -euo pipefail
source "$(dirname "$0")/share-lib.sh"

echo "=== ngrok is installed ==="
ngrok version

echo "=== refuses the booth's own port (10000) ==="
if out="$(ngrok-share 10000 2>&1)"; then fail "ngrok-share 10000 should be refused"; fi
echo "$out" | grep -q -- '--ok-booth' || fail "refusal does not mention --ok-booth: $out"
echo "ok"

echo "=== no authtoken: explains how to get one ==="
EMPTY_HOME="$(mktemp -d)"
if out="$(env -u NGROK_AUTHTOKEN HOME="$EMPTY_HOME" XDG_CONFIG_HOME="$EMPTY_HOME/.config" ngrok-share 8080 2>&1)"; then
    fail "ngrok-share without a token should fail"
fi
rm -rf "$EMPTY_HOME"
echo "$out" | grep -q 'dashboard.ngrok.com' || fail "no-token message lacks the dashboard link: $out"
echo "ok"

if [[ -z "${NGROK_AUTHTOKEN:-}" ]]; then
    echo "=== live share: SKIPPED (no NGROK_AUTHTOKEN on the host) ==="
    exit 0
fi

echo "=== shares the site on a public URL ==="
start_site
ngrok-share "$PORT" >"$LOG_DIR/share.log" 2>&1 &
PIDS+=($!)
url="$(wait_for_url "$LOG_DIR/share.log")" || fail "no Shared: URL from ngrok-share"
echo "URL: $url"
# The free plan's browser warning page is skipped for clients sending this header.
fetch_marker "$url" -H 'ngrok-skip-browser-warning: 1' || fail "$url does not serve the site"
echo "ok: the public URL serves the booth's page"
