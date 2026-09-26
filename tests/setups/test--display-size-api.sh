#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# POST /booth-messages/api/display-size — the booth page reports its frame size
# so a desktop that cannot follow noVNC's own resize request (the Wayland one:
# wayvnc 0.7 ignores it) is resized to fit. Runs the real
# booth-message-api-server on the host, one request at a time through its
# --handle mode (as socat does), with the cb-display-resize hook stubbed:
#   - no hook installed (X11 desktops, non-desktop variants): supported:false,
#     nothing run — the page then stops asking;
#   - with the hook: it is called with the size, clamped to 320x240…7680x4320;
#   - malformed or absurd sizes are rejected without calling it;
#   - a hook that fails (desktop not up yet) answers 503, still supported.
# That the Wayland desktop really follows is checked live (tests/complex/
# test-sway-wayland covers cb-display-resize against a real session).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API="$REPO_ROOT/variants/base/setups/booth-message-api-server"
BASH_BIN="$(command -v bash)"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/hook" "$STUB/failing"
LOG="$STUB/calls.log"
: > "$LOG"

for tool in head sed wc cat; do
    ln -s "$(command -v "$tool")" "$STUB/bin/$tool"
done
printf '#!/bin/bash\necho "cb-display-resize $*" >> "%s"\n' "$LOG" > "$STUB/hook/cb-display-resize"
printf '#!/bin/bash\necho "cb-display-resize $*" >> "%s"\nexit 1\n' "$LOG" > "$STUB/failing/cb-display-resize"
chmod +x "$STUB/hook/cb-display-resize" "$STUB/failing/cb-display-resize"

FAILED=0
NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    NUM=$((NUM + 1))
    print_test_result "$ok" "$0" "$NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/          /'
        FAILED=$((FAILED + 1))
    fi
}

# post <path> <json> — one request through --handle; sets OUT (status line + body).
post() {
    local path="$1" body="$2"
    OUT=$(printf 'POST /booth-messages/api/display-size HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s' \
            "${#body}" "$body" \
          | env -i HOME="$STUB" PATH="$path" "$BASH_BIN" "$API" --handle 2>&1 | tr -d '\r')
}

# ---- no hook: supported:false, nothing run ----
post "$STUB/bin" '{"width":1600,"height":900}'
if grep -q '^HTTP/1.0 200' <<< "$OUT" && grep -q '"supported":false' <<< "$OUT" && [[ ! -s "$LOG" ]]; then
    check "true"  "Without a resize hook: 200 supported:false, nothing run"
else
    check "false" "Without a resize hook: 200 supported:false, nothing run" "out=$OUT calls=$(cat "$LOG")"
fi

# ---- with the hook: called with the size ----
: > "$LOG"
post "$STUB/hook:$STUB/bin" '{"width":1600,"height":900}'
if grep -q '"supported":true' <<< "$OUT" && grep -qx 'cb-display-resize 1600 900' "$LOG"; then
    check "true"  "With the hook: it resizes to the reported 1600x900"
else
    check "false" "With the hook: it resizes to the reported 1600x900" "out=$OUT calls=$(cat "$LOG")"
fi

# ---- clamping ----
: > "$LOG"
post "$STUB/hook:$STUB/bin" '{"width":100,"height":50}'
post "$STUB/hook:$STUB/bin" '{"height":9000,"width":9000}'
if [[ "$(cat "$LOG")" == $'cb-display-resize 320 240\ncb-display-resize 7680 4320' ]]; then
    check "true"  "Sizes are clamped to 320x240 … 7680x4320 (key order does not matter)"
else
    check "false" "Sizes are clamped to 320x240 … 7680x4320 (key order does not matter)" "calls=$(cat "$LOG")"
fi

# ---- rejected without calling the hook ----
: > "$LOG"
REJECTED=0
for body in '{"width":"wide","height":900}' '{"width":1600}' '{}' '{"width":-5,"height":900}' '{"width":99999999999,"height":900}'; do
    post "$STUB/hook:$STUB/bin" "$body"
    grep -q '^HTTP/1.0 400' <<< "$OUT" && REJECTED=$((REJECTED + 1))
done
if [[ "$REJECTED" -eq 5 && ! -s "$LOG" ]]; then
    check "true"  "Malformed, missing, negative and absurd sizes: 400, hook not run"
else
    check "false" "Malformed, missing, negative and absurd sizes: 400, hook not run" "rejected=$REJECTED/5 calls=$(cat "$LOG")"
fi

# ---- the hook fails (desktop not up yet): 503, still supported ----
post "$STUB/failing:$STUB/bin" '{"width":1600,"height":900}'
if grep -q '^HTTP/1.0 503 Service Unavailable' <<< "$OUT" && grep -q '"supported":true' <<< "$OUT"; then
    check "true"  "A failing hook answers 503, still supported (the page retries)"
else
    check "false" "A failing hook answers 503, still supported (the page retries)" "out=$OUT"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
