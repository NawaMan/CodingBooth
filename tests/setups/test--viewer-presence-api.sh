#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# /booth-messages/api/presence — counts the pages viewing a booth. Every page
# that loads the overlay beats with its own random id; the count drops when a
# page releases (its tab closed) or stops beating. Runs the real
# booth-message-api-server on the host, one request at a time through its
# --handle mode (as socat does), with the presence dir in a temp dir:
#   - two pages beating count as two; a renewal does not add a third;
#   - a hidden page counts, and is reported as in the background;
#   - a release drops the page at once;
#   - a visible page that stopped beating for longer than its TTL is swept;
#   - a hidden page is kept past that TTL (browsers slow a background tab's
#     timers to about once a minute) and swept only after its own, longer one;
#   - GET reads the count without registering anything;
#   - a missing or malformed id is rejected and changes nothing;
#   - every answer says how many viewers are expected (BOOTH_EXPECTED_VIEWER_COUNT,
#     1 when unset or not a count), which the overlay shows the count above.
# That the overlay beats, releases on close and shows the count is checked
# live against a booth, not here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API="$REPO_ROOT/variants/base/setups/booth-message-api-server"
BASH_BIN="$(command -v bash)"

require_host_tools "booth-message-api-server matches its request headers with \${line,,}" bash4

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin"
DIR="$STUB/presence"

for tool in head sed wc cat mv rm mkdir; do
    ln -s "$(command -v "$tool")" "$STUB/bin/$tool"
done

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

# request <method> [json] — one request through --handle; sets OUT (status line + body).
# EXPECTED, when set, is passed as BOOTH_EXPECTED_VIEWER_COUNT.
EXPECTED=""
request() {
    local method="$1" body="${2:-}"
    local expected_env=()
    [[ -n "$EXPECTED" ]] && expected_env=(BOOTH_EXPECTED_VIEWER_COUNT="$EXPECTED")
    OUT=$(printf '%s /booth-messages/api/presence HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s' \
            "$method" "${#body}" "$body" \
          | env -i HOME="$STUB" PATH="$(stub_path "$STUB/bin")" BOOTH_PRESENCE_DIR="$DIR" "${expected_env[@]}" \
                "$BASH_BIN" "$API" --handle 2>&1 | tr -d '\r')
}
beat() { request POST "$1"; }
# counts <viewers> <background> — the last answer was a 200 with these counts.
counts() { grep -q '^HTTP/1.0 200' <<< "$OUT" && grep -q "\"viewers\":$1,\"background\":$2," <<< "$OUT"; }
# age <id> <state> <seconds> — make a page's last beat that long ago.
age() { printf '%s %s\n' "$2" "$(( $(date +%s) - $3 ))" > "$DIR/$1"; }

# ---- two pages count as two; a renewal does not add one ----
beat '{"id":"tabA","visible":true}'
beat '{"id":"tabB","visible":true}'
beat '{"id":"tabA","visible":true}'
if counts 2 0; then
    check "true"  "Two pages beating count as two viewers; a renewal does not add a third"
else
    check "false" "Two pages beating count as two viewers; a renewal does not add a third" "out=$OUT"
fi

# ---- a hidden page counts, in the background ----
beat '{"id":"tabB","visible":false}'
if counts 2 1; then
    check "true"  "A hidden page still counts, and is reported as in the background"
else
    check "false" "A hidden page still counts, and is reported as in the background" "out=$OUT"
fi

# ---- a release drops the page at once ----
beat '{"id":"tabB","release":true}'
if counts 1 0 && [[ ! -e "$DIR/tabB" ]]; then
    check "true"  "A release (the tab closed) drops the page at once"
else
    check "false" "A release (the tab closed) drops the page at once" "out=$OUT"
fi

# ---- a visible page that stopped beating is swept ----
age tabA visible 20
beat '{"id":"tabC","visible":true}'
if counts 1 0 && [[ ! -e "$DIR/tabA" ]]; then
    check "true"  "A visible page silent past its TTL (crash, lost network) is swept"
else
    check "false" "A visible page silent past its TTL (crash, lost network) is swept" "out=$OUT"
fi

# ---- a hidden page outlives that TTL, but not its own ----
age tabD hidden 60
request GET
KEPT="$OUT"
age tabD hidden 100
request GET
if counts 1 0 && grep -q '"viewers":2,"background":1,' <<< "$KEPT" && [[ ! -e "$DIR/tabD" ]]; then
    check "true"  "A hidden page is kept through throttled heartbeats and swept after its longer TTL"
else
    check "false" "A hidden page is kept through throttled heartbeats and swept after its longer TTL" "kept=$KEPT out=$OUT"
fi

# ---- GET reads without registering ----
BEFORE=$(ls "$DIR" | wc -l)
request GET
if counts 1 0 && [[ "$(ls "$DIR" | wc -l)" -eq "$BEFORE" ]]; then
    check "true"  "GET reads the count and registers nothing"
else
    check "false" "GET reads the count and registers nothing" "out=$OUT"
fi

# ---- bad ids are rejected and change nothing ----
REJECTED=0
for body in '{}' '{"visible":true}' '{"id":"","visible":true}' '{"id":"a b","visible":true}' \
            '{"id":"../x","visible":true}' "{\"id\":\"$(printf 'x%.0s' {1..65})\",\"visible\":true}"; do
    beat "$body"
    grep -q '^HTTP/1.0 400' <<< "$OUT" && REJECTED=$((REJECTED + 1))
done
request GET
if [[ "$REJECTED" -eq 6 ]] && counts 1 0 && [[ ! -e "$STUB/x" ]]; then
    check "true"  "Missing, empty, odd-character and over-long ids: 400, count unchanged"
else
    check "false" "Missing, empty, odd-character and over-long ids: 400, count unchanged" "rejected=$REJECTED/6 out=$OUT"
fi

# ---- the expected count rides along on every answer ----
request GET
DEFAULT="$OUT"
EXPECTED=3
request GET
SET="$OUT"
EXPECTED=0
request GET
ZERO="$OUT"
EXPECTED=lots
request GET
BAD="$OUT"
EXPECTED=""
if grep -q '"expected":1}' <<< "$DEFAULT" && grep -q '"expected":3}' <<< "$SET" \
        && grep -q '"expected":0}' <<< "$ZERO" && grep -q '"expected":1}' <<< "$BAD"; then
    check "true"  "The answer carries the expected count: 1 unset, as set, 0 kept, 1 for a non-count"
else
    check "false" "The answer carries the expected count: 1 unset, as set, 0 kept, 1 for a non-count" \
        "default=$DEFAULT set=$SET zero=$ZERO bad=$BAD"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
