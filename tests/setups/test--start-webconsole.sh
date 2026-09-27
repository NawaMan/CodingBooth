#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: start-webconsole — the web console started by hand next to another
# variant's own service (JupyterLab, code-server) on 11111 by default.
#
# start-webconsole only picks and checks the port, then hands it to start-ttyd,
# which is stubbed here to record what it was given. The console layout it
# drives (panes on +1..+4, message API on +7) is checked on the nginx template
# and start-ttyd-split directly.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE="$REPO_ROOT/variants/base"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/start-ttyd" <<'STUB'
#!/bin/bash
echo "start-ttyd $*"
STUB
chmod +x "$WORK/bin/start-ttyd"

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

run_webconsole() {
    RUN_OUT=$(PATH="$WORK/bin:$PATH" bash "$BASE/start-webconsole" "$@" 2>&1 </dev/null) && RUN_EXIT=0 || RUN_EXIT=$?
}

# A port nobody on this host is listening on, so the "in use" guard stays quiet.
free_port() {
    local p
    for p in $(seq 41111 41200); do
        (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null || { echo "$p"; return; }
    done
}

# The default is only asserted when 11111 is free here; otherwise the guard below
# (correctly) refuses it, which is not what this case is about.
if (exec 3<>/dev/tcp/127.0.0.1/11111) 2>/dev/null; then
    check "start-webconsole defaults to 11111 (skipped: 11111 is in use on this host)" "true"
else
    run_webconsole
    check "start-webconsole defaults to 11111" \
        "$([[ "$RUN_EXIT" == 0 && "$RUN_OUT" == *"start-ttyd 11111"* ]] && echo true || echo false)" "$RUN_OUT"
    check "start-webconsole says how to reach it from the host" \
        "$([[ "$RUN_OUT" == *"booth--expose 11111"* ]] && echo true || echo false)" "$RUN_OUT"
fi

port=$(free_port)
run_webconsole "$port"
check "start-webconsole <port> starts the console on that port" \
    "$([[ "$RUN_EXIT" == 0 && "$RUN_OUT" == *"start-ttyd $port"* ]] && echo true || echo false)" "$RUN_OUT"

run_webconsole notaport
check "start-webconsole notaport: refused with a usage line" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"Usage: start-webconsole [port]"* && "$RUN_OUT" != *"start-ttyd"* ]] && echo true || echo false)" "$RUN_OUT"

run_webconsole 65530
check "start-webconsole 65530: refused, its API port (+7) would not exist" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" != *"start-ttyd"* ]] && echo true || echo false)" "$RUN_OUT"

# A port already taken is refused up front, rather than failing inside nginx.
busy=$(free_port)
python3 -c "import socket,time;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',$busy));s.listen();time.sleep(30)" &
LISTENER=$!
for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$busy") 2>/dev/null && break; sleep 0.1; done
run_webconsole "$busy"
kill "$LISTENER" 2>/dev/null || true
check "start-webconsole on a port in use: refused" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"already in use"* && "$RUN_OUT" != *"start-ttyd"* ]] && echo true || echo false)" "$RUN_OUT"

# ---- the console's own helpers sit above its port, not on fixed ones --------
TEMPLATE="$BASE/web-ttyd-split/nginx.conf.template"
check "console nginx template has no fixed helper ports left" \
    "$(! grep -qE '127\.0\.0\.1:1000[1-7]' "$TEMPLATE" && echo true || echo false)" \
    "$(grep -nE '127\.0\.0\.1:1000[1-7]' "$TEMPLATE" || true)"
check "start-ttyd-split puts the panes on +1..+4 and the API on +7" \
    "$(grep -qF 'SESSION_PORTS=($((PORT + 1)) $((PORT + 2)) $((PORT + 3)) $((PORT + 4)))' "$BASE/start-ttyd-split" \
        && grep -qF 'API_PORT=$((PORT + 7))' "$BASE/start-ttyd-split" && echo true || echo false)"
check "start-ttyd-split starts the once-per-booth helpers only when absent" \
    "$(grep -qF 'pgrep -f booth-lifecycle-watcher >/dev/null || booth-lifecycle-watcher &' "$BASE/start-ttyd-split" \
        && grep -qF 'pgrep -f booth-timer-notifier >/dev/null || booth-timer-notifier &' "$BASE/start-ttyd-split" \
        && echo true || echo false)"
check "base image installs start-webconsole" \
    "$(grep -qF 'COPY --chmod=0755 start-webconsole /usr/local/bin/start-webconsole' "$BASE/Dockerfile" && echo true || echo false)"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
