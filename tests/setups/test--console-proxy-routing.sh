#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: where the console's nginx sends an app's root-absolute requests
#
# Renders this tree's web-ttyd-split/nginx.conf.template, runs it in a
# throwaway base-image container next to two stand-in apps (ports 5173 and
# 8080, each answering "app-<port>"), and asks it for /v1/… and other root
# paths the way a proxied SPA does:
#
# 1) Referer /proxy/<port>/ picks that port.
# 2) The Referer wins over a cb_proxy_port cookie for another port — a globe
#    pane left on a Vite app must not take the Appwrite console's /v1 calls.
# 3) No /proxy/ Referer (a module imported by a root-served module) falls back
#    to the cookie.
# 4) Opening a /proxy/<port>/ page as a document sets cb_proxy_port=<port>;
#    a subresource does not.
# 5) With neither, the root still serves the console itself.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE="$REPO_ROOT/variants/base"
VERSION="$(tr -d ' \t\n\r' < "$REPO_ROOT/version.txt")"
IMAGE="nawaman/codingbooth:base-${VERSION}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "SKIP: $IMAGE not present locally (nginx + envsubst come from the base image)." >&2
    exit 0
fi

ALL_PASSED=true
TEST_NUM=0
check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -8
        ALL_PASSED=false
    fi
}

NAME="cb-proxy-routing-$$"
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Console on 10000 (no password), stand-in apps on 5173 and 8080.
docker run -d --rm --name "$NAME" --entrypoint bash \
    -v "$BASE/web-ttyd-split/nginx.conf.template:/t/nginx.conf.template:ro" \
    -v "$BASE/setups/libs/booth-proxy-response.conf:/opt/codingbooth/setups/libs/booth-proxy-response.conf:ro" \
    "$IMAGE" -c '
set -e
mkdir -p /tmp/serve /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi  # as start-ttyd-split does
echo console-ui > /tmp/serve/index.html
export PORT=10000 WEB_SPLIT_SERVE=/tmp/serve FILE_TAG=-routing BOOTH_INSTANCE_ID=test
export S1_PORT=10001 S2_PORT=10002 S3_PORT=10003 S4_PORT=10004 S5_PORT=10005 S6_PORT=10006 API_PORT=10007
export TTYD_AUTH_HEADER= FAVICON_LOCATIONS=
export AUTH_MAP="map \$cookie_booth_auth \$booth_auth_ok { default 1; }"
envsubst "\${PORT} \${WEB_SPLIT_SERVE} \${AUTH_MAP} \${TTYD_AUTH_HEADER} \${BOOTH_INSTANCE_ID} \${S1_PORT} \${S2_PORT} \${S3_PORT} \${S4_PORT} \${S5_PORT} \${S6_PORT} \${API_PORT} \${FILE_TAG} \${FAVICON_LOCATIONS}" \
    < /t/nginx.conf.template > /tmp/console.conf
cat > /tmp/apps.conf <<EOF
pid /tmp/apps.pid;
error_log /tmp/apps-error.log;
events {}
http {
    access_log off;
    server { listen 5173; location / { return 200 "app-5173\n"; } }
    server { listen 8080; location / { return 200 "app-8080\n"; } }
}
EOF
nginx -c /tmp/apps.conf
nginx -c /tmp/console.conf
sleep 600
' >/dev/null

# ask <curl args…> — body (first line) from inside the container.
ask() { docker exec "$NAME" curl -s -m 5 "$@" 2>/dev/null | head -1; }

ready=false
for _ in $(seq 1 30); do
    [[ "$(ask http://127.0.0.1:10000/proxy/5173/)" == "app-5173" ]] && { ready=true; break; }
    sleep 0.5
done
if ! $ready; then
    check "console nginx and stand-in apps start" false "$(docker logs "$NAME" 2>&1 | tail -5)"
    exit 1
fi

REF_5173="Referer: http://localhost:10000/proxy/5173/src/app.js"
REF_8080="Referer: http://localhost:10000/proxy/8080/console/login"

got="$(ask -H "$REF_8080" http://127.0.0.1:10000/v1/account)"
check "Referer /proxy/8080/ sends /v1/… to 8080" "$([[ "$got" == app-8080 ]] && echo true || echo false)" "got: $got"

got="$(ask -H "$REF_5173" http://127.0.0.1:10000/@vite/client)"
check "Referer /proxy/5173/ sends a root path to 5173" "$([[ "$got" == app-5173 ]] && echo true || echo false)" "got: $got"

got="$(ask -H "$REF_8080" -H 'Cookie: cb_proxy_port=5173' http://127.0.0.1:10000/v1/account)"
check "Referer wins over a cookie for another port (/v1/)" "$([[ "$got" == app-8080 ]] && echo true || echo false)" "got: $got"

got="$(ask -H "$REF_8080" -H 'Cookie: cb_proxy_port=5173' http://127.0.0.1:10000/assets/x.js)"
check "Referer wins over a cookie for another port (catch-all)" "$([[ "$got" == app-8080 ]] && echo true || echo false)" "got: $got"

got="$(ask -H 'Referer: http://localhost:10000/.svelte-kit/generated/root.js' -H 'Cookie: cb_proxy_port=5173' http://127.0.0.1:10000/node_modules/.vite/deps/svelte.js)"
check "No /proxy/ Referer falls back to the cookie" "$([[ "$got" == app-5173 ]] && echo true || echo false)" "got: $got"

hdr="$(docker exec "$NAME" curl -s -m 5 -D - -o /dev/null -H 'Sec-Fetch-Dest: document' http://127.0.0.1:10000/proxy/5173/ | tr -d '\r')"
check "A /proxy/5173/ page opened as a document sets cb_proxy_port=5173" \
    "$(grep -qi '^Set-Cookie: cb_proxy_port=5173; Path=/' <<< "$hdr" && echo true || echo false)" "$hdr"

hdr="$(docker exec "$NAME" curl -s -m 5 -D - -o /dev/null -H 'Sec-Fetch-Dest: iframe' http://127.0.0.1:10000/proxy/8080/ | tr -d '\r')"
check "A /proxy/8080/ page in an iframe (globe pane) sets cb_proxy_port=8080" \
    "$(grep -qi '^Set-Cookie: cb_proxy_port=8080; Path=/' <<< "$hdr" && echo true || echo false)" "$hdr"

hdr="$(docker exec "$NAME" curl -s -m 5 -D - -o /dev/null -H 'Sec-Fetch-Dest: script' http://127.0.0.1:10000/proxy/5173/main.js | tr -d '\r')"
check "A subresource under /proxy/ leaves the cookie alone" \
    "$(grep -qi '^Set-Cookie:' <<< "$hdr" && echo false || echo true)" "$hdr"

got="$(ask http://127.0.0.1:10000/some/path)"
check "No Referer and no cookie: the root serves the console" "$([[ "$got" == console-ui ]] && echo true || echo false)" "got: $got"

$ALL_PASSED
