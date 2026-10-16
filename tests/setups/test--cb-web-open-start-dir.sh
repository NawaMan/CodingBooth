#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# cb-web-open starts a not-yet-running service from the project folder, not
# from the launcher's working directory. XFCE runs a desktop icon in ~/Desktop,
# and JupyterLab serves its working directory, so the notebook icon used to
# open on the Desktop. The start command is a stub that records its cwd and
# then listens on the port; the browser is a stub that records the URL.
# No container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OPENER="$REPO_ROOT/variants/base/setups/cb-web-open"

WORK=$(mktemp -d)
SERVER_PID=""
cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
    pkill -f "http.server --bind 127.0.0.1 ${PORT:-0}\$" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -20
        ALL_PASSED=false
    fi
}

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 is needed for the stub service"
    exit 0
fi

PORT="$(pick_free_port)"
STUBS="$WORK/stubs"
CONF_DIR="$WORK/conf"
PROJECT="$WORK/code"
DESKTOP="$WORK/Desktop"
mkdir -p "$STUBS" "$CONF_DIR" "$PROJECT" "$DESKTOP"

# Start command: record the cwd, then become the service.
cat >"$STUBS/start-stub" <<EOF
#!/bin/bash
pwd >"$WORK/start-cwd"
exec python3 -m http.server --bind 127.0.0.1 $PORT
EOF
# Browser: record the URL instead of opening a window.
cat >"$STUBS/google-chrome" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >"$WORK/browser-args"
EOF
chmod +x "$STUBS/start-stub" "$STUBS/google-chrome"

cat >"$CONF_DIR/stub.conf" <<EOF
PORT_ENV=""
PORT_DEFAULT="$PORT"
URL_PATH="/lab"
TOKEN_ENV=""
START_CMD="start-stub"
EOF

# --- not running: started from the project folder, launched from ~/Desktop ---
(cd "$DESKTOP" && PATH="$STUBS:$PATH" CB_WEB_CONF_DIR="$CONF_DIR" CB_WEB_START_DIR="$PROJECT" \
    bash "$OPENER" stub >"$WORK/out" 2>&1) && EXIT=0 || EXIT=$?
SERVER_PID=$(pgrep -f "http.server --bind 127.0.0.1 ${PORT}\$" || true)

check "opener exits 0" "$([[ $EXIT -eq 0 ]] && echo true || echo false)" "$(cat "$WORK/out")"
check "start command runs in the project folder, not the launcher's cwd" \
    "$([[ "$(cat "$WORK/start-cwd" 2>/dev/null)" == "$PROJECT" ]] && echo true || echo false)" \
    "cwd: $(cat "$WORK/start-cwd" 2>/dev/null || echo '<start command never ran>')"
check "browser opens the service URL" \
    "$(grep -qF -- "--app=http://localhost:${PORT}/lab" "$WORK/browser-args" 2>/dev/null && echo true || echo false)" \
    "$(cat "$WORK/browser-args" 2>/dev/null)"

# --- already running: the start command is not run again ---
rm -f "$WORK/start-cwd"
(cd "$DESKTOP" && PATH="$STUBS:$PATH" CB_WEB_CONF_DIR="$CONF_DIR" CB_WEB_START_DIR="$PROJECT" \
    bash "$OPENER" stub >"$WORK/out" 2>&1) && EXIT=0 || EXIT=$?
check "running service is not started again" \
    "$([[ ! -e "$WORK/start-cwd" ]] && echo true || echo false)" "$(cat "$WORK/out")"

# --- project folder missing: falls back to \$HOME rather than staying put ---
kill "$SERVER_PID" 2>/dev/null || true
for _ in $(seq 1 20); do (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null || break; sleep 0.2; done
FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME"
(cd "$DESKTOP" && HOME="$FAKE_HOME" PATH="$STUBS:$PATH" CB_WEB_CONF_DIR="$CONF_DIR" \
    CB_WEB_START_DIR="$WORK/no-such-dir" bash "$OPENER" stub >"$WORK/out" 2>&1) && EXIT=0 || EXIT=$?
SERVER_PID=$(pgrep -f "http.server --bind 127.0.0.1 ${PORT}\$" || true)
check "missing project folder falls back to \$HOME" \
    "$([[ "$(cat "$WORK/start-cwd" 2>/dev/null)" == "$FAKE_HOME" ]] && echo true || echo false)" \
    "cwd: $(cat "$WORK/start-cwd" 2>/dev/null || echo '<start command never ran>')"

if [[ "$ALL_PASSED" == "true" ]]; then
    exit 0
else
    exit 1
fi
