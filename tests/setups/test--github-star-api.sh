#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# /booth-messages/api/star — whether the overlay should ask for a GitHub star.
# Runs the real booth-message-api-server on the host, one request at a time
# through its --handle mode (as socat does), with the click marker in a temp dir:
#   - GET answers BOOTH_STAR_PROMPT: on when unset or not a known value, off, done;
#   - POST records the click in the marker, and GET then answers done;
#   - off stays off whatever the marker says (the host turned it off).
# The overlay's timing and toast are checked with a stubbed DOM, not here.

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
MARKER="$STUB/tmp/github-star"

for tool in head sed cat mkdir dirname; do
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

# request <method> [prompt] — one request through --handle; sets OUT.
request() {
    local method="$1" prompt="${2-}"
    local prompt_env=()
    [[ -n "$prompt" ]] && prompt_env=(BOOTH_STAR_PROMPT="$prompt")
    OUT=$(printf '%s /booth-messages/api/star HTTP/1.1\r\nContent-Length: 0\r\n\r\n' "$method" \
          | env -i HOME="$STUB" PATH="$(stub_path "$STUB/bin")" BOOTH_STAR_MARKER="$MARKER" "${prompt_env[@]}" \
                "$BASH_BIN" "$API" --handle 2>&1 | tr -d '\r')
}
answers() { grep -q '^HTTP/1.0 200' <<< "$OUT" && grep -q "\"prompt\":\"$1\"" <<< "$OUT"; }

# ---- GET reports BOOTH_STAR_PROMPT ----
request GET;        UNSET="$OUT"
request GET on;     ON="$OUT"
request GET off;    OFF="$OUT"
request GET done;   DONE="$OUT"
request GET maybe;  ODD="$OUT"
if OUT="$UNSET" answers on && OUT="$ON" answers on && OUT="$OFF" answers off \
        && OUT="$DONE" answers done && OUT="$ODD" answers on; then
    check "true"  "GET answers BOOTH_STAR_PROMPT: on (unset or unknown), off, done"
else
    check "false" "GET answers BOOTH_STAR_PROMPT: on (unset or unknown), off, done" \
        "unset=$UNSET on=$ON off=$OFF done=$DONE odd=$ODD"
fi

# ---- POST records the click; GET then says done ----
request POST
POSTED="$OUT"
request GET on
if grep -q '^HTTP/1.0 200' <<< "$POSTED" && [[ -s "$MARKER" ]] && answers done; then
    check "true"  "POST writes the click marker, and the booth then answers done"
else
    check "false" "POST writes the click marker, and the booth then answers done" "post=$POSTED get=$OUT"
fi

# ---- off wins over the marker ----
request GET off
if answers off; then
    check "true"  "off stays off with the marker present"
else
    check "false" "off stays off with the marker present" "$OUT"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
