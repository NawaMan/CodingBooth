#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the Console UI's "Reset session" endpoint in
# booth-message-api-server (POST /booth-messages/api/session-reset). The real
# script answers one request on stdin (--handle); tmux and booth--lifecycle-log
# are stubbed to record what they were asked. Only the six pane sessions, by
# exact name, may be ended — anything else is refused without calling tmux.
# The page side (the key, the button, the confirmation) is test030's.
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API="$REPO_ROOT/variants/base/setups/booth-message-api-server"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

mkdir -p "$WORK/bin"
for tool in tmux booth--lifecycle-log; do
    cat > "$WORK/bin/$tool" <<STUB
#!/bin/bash
echo "$tool \$*" >> "$WORK/calls"
STUB
    chmod +x "$WORK/bin/$tool"
done

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

# One POST with $1 as its body; sets RESPONSE and CALLS.
reset_with() {
    : > "$WORK/calls"
    RESPONSE=$(printf 'POST /booth-messages/api/session-reset HTTP/1.1\r\nContent-Length: %s\r\n\r\n%s' "${#1}" "$1" \
        | PATH="$WORK/bin:$PATH" bash "$API" --handle 2>&1)
    CALLS=$(cat "$WORK/calls")
}

reset_with '{"session":3}'
check "session 3 ends tmux session s3, by exact name" \
    "$([[ "$RESPONSE" == *"200 OK"* && "$RESPONSE" == *'"session":3'* && "$CALLS" == *"tmux kill-session -t =s3"* ]] && echo true || echo false)" \
    "$RESPONSE"$'\n'"$CALLS"
check "the reset is written to the lifecycle log" \
    "$([[ "$CALLS" == *"booth--lifecycle-log console-session-reset session=s3"* ]] && echo true || echo false)" "$CALLS"

reset_with '{"session":"6"}'
check "session given as a string still resets (s6)" \
    "$([[ "$RESPONSE" == *"200 OK"* && "$CALLS" == *"tmux kill-session -t =s6"* ]] && echo true || echo false)" "$CALLS"

for bad in '{"session":7}' '{"session":0}' '{"session":"3; rm -rf ~"}' '{"session":"s3"}' '{}' 'not json'; do
    reset_with "$bad"
    check "refused without touching tmux: $bad" \
        "$([[ "$RESPONSE" == *"400 Bad Request"* && "$CALLS" != *tmux* ]] && echo true || echo false)" \
        "$RESPONSE"$'\n'"$CALLS"
done

if [[ "$ALL_PASSED" != true ]]; then
    exit 1
fi
