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
# The endpoint hands the work to booth--console-reset, run for real here; its
# --force is exercised on real processes, with tmux list-panes stubbed to
# report them as the session's pane.
# The page side (the key, the button, the confirmation) is test030's.
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API="$REPO_ROOT/variants/base/setups/booth-message-api-server"
RESET="$REPO_ROOT/variants/base/setups/booth--console-reset"

require_host_tools "booth-message-api-server matches its request headers with \${line,,}" bash4

# handle_session_reset reads the request body with jq, which every booth has and
# a host may not. Without it the endpoint answers 400 to everything and the
# refusal cases would pass for the wrong reason.
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed on this host, and booth-message-api-server parses its body with it"
  exit 0
fi

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
# list-panes answers from $WORK/panes ("<pane_id> <pane_pid>" lines), empty
# unless a case writes it.
cat >> "$WORK/bin/tmux" <<STUB
[[ "\$1" == list-panes ]] && cat "$WORK/panes" 2>/dev/null
exit 0
STUB
: > "$WORK/panes"
ln -s "$RESET" "$WORK/bin/booth--console-reset"

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
check "the reset is written to the lifecycle log, not forced" \
    "$([[ "$CALLS" == *"booth--lifecycle-log console-session-reset session=s3 force=false"* ]] && echo true || echo false)" "$CALLS"
check "a plain reset lists no processes to kill" \
    "$([[ "$CALLS" != *list-panes* && "$RESPONSE" == *'"force":false'* ]] && echo true || echo false)" "$RESPONSE"$'\n'"$CALLS"

reset_with '{"session":2,"force":true}'
check "force:true resets s2 forced, listing its panes first" \
    "$([[ "$RESPONSE" == *"200 OK"* && "$RESPONSE" == *'"force":true'* && "$CALLS" == *"tmux list-panes -s -t =s2"* \
         && "$CALLS" == *"tmux kill-session -t =s2"* && "$CALLS" == *"session=s2 force=true"* ]] && echo true || echo false)" \
    "$RESPONSE"$'\n'"$CALLS"

reset_with '{"session":2,"force":"yes"}'
check "force must be the JSON true, anything else is a plain reset" \
    "$([[ "$RESPONSE" == *'"force":false'* && "$CALLS" != *list-panes* ]] && echo true || echo false)" "$RESPONSE"$'\n'"$CALLS"

reset_with '{"session":"6"}'
check "session given as a string still resets (s6)" \
    "$([[ "$RESPONSE" == *"200 OK"* && "$CALLS" == *"tmux kill-session -t =s6"* ]] && echo true || echo false)" "$CALLS"

for bad in '{"session":7}' '{"session":0}' '{"session":"3; rm -rf ~"}' '{"session":"s3"}' '{}' 'not json'; do
    reset_with "$bad"
    check "refused without touching tmux: $bad" \
        "$([[ "$RESPONSE" == *"400 Bad Request"* && "$CALLS" != *tmux* ]] && echo true || echo false)" \
        "$RESPONSE"$'\n'"$CALLS"
done

# The command itself refuses anything but a pane number.
for bad in 0 7 s3 "3; true" ""; do
    : > "$WORK/calls"
    status=0; out=$(PATH="$WORK/bin:$PATH" bash "$RESET" "$bad" 2>&1) || status=$?
    check "booth--console-reset refuses '$bad' without touching tmux" \
        "$([[ $status -eq 2 && "$(cat "$WORK/calls")" != *tmux* ]] && echo true || echo false)" "$out"
done

# --force on real processes: a pane shell whose child ignores HUP and TERM,
# and an escapee that left the tree (setsid) but still carries TMUX_PANE.
# A bystander with no tie to the pane must survive.
PANE_ID="%cbtest$$"
bash -c 'trap "" HUP TERM; sleep 300 & wait' &
ROOT=$!
TMUX_PANE="$PANE_ID" setsid bash -c 'trap "" HUP TERM; exec sleep 301' &
sleep 0.3
ESCAPEE=$(pgrep -f -x "sleep 301" | head -1)
bash -c 'trap "" HUP TERM; exec sleep 302' &
BYSTANDER=$!
disown -a   # no "Killed" job notices when --force does its work
sleep 0.3
CHILD=$(pgrep -P "$ROOT" sleep | head -1)
echo "$PANE_ID $ROOT" > "$WORK/panes"

out=$(PATH="$WORK/bin:$PATH" bash "$RESET" 4 --force 2>&1)
sleep 0.3
alive() { kill -0 "$1" 2>/dev/null && [[ "$(ps -o stat= -p "$1" 2>/dev/null)" != Z* ]]; }
check "--force kills the pane's tree, even a child ignoring HUP and TERM" \
    "$( ! alive "$ROOT" && [[ -n "$CHILD" ]] && ! alive "$CHILD" && echo true || echo false)" "$out (root=$ROOT child=$CHILD)"
check "--force kills an escapee still carrying the pane's TMUX_PANE" \
    "$([[ -n "$ESCAPEE" ]] && ! alive "$ESCAPEE" && echo true || echo false)" "$out (escapee=$ESCAPEE)"
check "--force leaves an unrelated process alone" \
    "$(alive "$BYSTANDER" && echo true || echo false)" "$out"
kill -KILL "$ROOT" "$CHILD" "$ESCAPEE" "$BYSTANDER" 2>/dev/null || true
: > "$WORK/panes"

if [[ "$ALL_PASSED" != true ]]; then
    exit 1
fi
