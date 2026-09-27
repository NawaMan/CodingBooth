#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: start-codeserver, as launched by hand next to another code-server
#
# Run from a code-server terminal, start-codeserver used to start nothing: that
# terminal sets VSCODE_IPC_HOOK_CLI, which turns `code-server` into a client of
# the running window (it opens the folder there and ignores --bind-addr). And a
# second instance on the same data directory takes over the first one's session
# socket. The launcher is a heredoc inside codeserver--setup.sh, so it is
# extracted and run with a stub `code-server` that records how it was called,
# and a stub `pgrep` that says whether another code-server is running.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/variants/base/setups/codeserver--setup.sh"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

# The launcher: `envsubst '$CODESERVER_EXTENSION_DIR' > ${STARTER_FILE} <<'LAUNCH'`
# ... `LAUNCH`, with its default port stamped in the way the setup does.
LAUNCHER="$WORK/start-codeserver"
awk '/<<.LAUNCH.$/{f=1;next} f&&/^LAUNCH$/{exit} f' "$SETUP" \
    | sed 's/__CODESERVER_DEFAULT_PORT__/13333/g' > "$LAUNCHER"
if ! grep -q 'exec "$CODE_SERVER_BIN"' "$LAUNCHER"; then
    echo "❌ Could not extract the start-codeserver launcher from $SETUP"
    exit 1
fi

mkdir -p "$WORK/bin"
cat > "$WORK/bin/code-server" <<'STUB'
#!/bin/bash
echo "code-server $*"
echo "IPC_HOOK=[${VSCODE_IPC_HOOK_CLI:-}]"
STUB
cat > "$WORK/bin/pgrep" <<'STUB'
#!/bin/bash
[[ "${STUB_OTHER_CODESERVER:-0}" == 1 ]]
STUB
chmod +x "$WORK/bin/code-server" "$WORK/bin/pgrep"

# What a code-server terminal puts first on PATH: VS Code's remote CLI, whose
# `code-server` only talks to that window and refuses without its IPC variable.
mkdir -p "$WORK/vscode/bin/remote-cli"
cat > "$WORK/vscode/bin/remote-cli/code-server" <<'STUB'
#!/bin/bash
echo "Command is only available in WSL or inside a Visual Studio Code terminal."
exit 1
STUB
chmod +x "$WORK/vscode/bin/remote-cli/code-server"

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

# A port nobody on this host is listening on.
free_port() {
    local p
    for p in $(seq 43333 43400); do
        (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null || { echo "$p"; return; }
    done
}

run_launcher() {
    local home
    home=$(mktemp -d "$WORK/home-XXXX")
    mkdir -p "$home/code"
    RUN_HOME="$home"
    # The deferred-extension marker lives under /usr/local/share; point the
    # extension dir anywhere, the stub ignores it.
    RUN_OUT=$(env -i PATH="${RUN_PATH:-$WORK/bin:/usr/bin:/bin}" HOME="$home" CODESERVER_EXTENSION_DIR="$WORK/ext" \
        "$@" bash "$LAUNCHER" "${LAUNCH_ARGS[@]}" 2>&1 </dev/null) && RUN_EXIT=0 || RUN_EXIT=$?
}

port=$(free_port)

# --- from a code-server terminal: still a server -----------------------------
LAUNCH_ARGS=("$port")
run_launcher VSCODE_IPC_HOOK_CLI=/tmp/vscode-ipc-running-window.sock
check "clears VSCODE_IPC_HOOK_CLI, so code-server starts a server" \
    "$([[ "$RUN_OUT" == *"IPC_HOOK=[]"* ]] && echo true || echo false)" "$RUN_OUT"
check "binds the port it was given" \
    "$([[ "$RUN_OUT" == *"--bind-addr 0.0.0.0:$port"* ]] && echo true || echo false)" "$RUN_OUT"

# --- the remote CLI first on PATH, as in a code-server terminal ---------------
RUN_PATH="$WORK/vscode/bin/remote-cli:$WORK/bin:/usr/bin:/bin" run_launcher VSCODE_IPC_HOOK_CLI=/tmp/vscode-ipc-running-window.sock
check "runs the real code-server, not the terminal's remote-CLI shim" \
    "$([[ "$RUN_OUT" == *"code-server --extensions-dir"* && "$RUN_OUT" != *"only available in WSL"* ]] && echo true || echo false)" "$RUN_OUT"

# --- alone: the usual data directory, as the codeserver variant's own --------
run_launcher STUB_OTHER_CODESERVER=0
check "alone, it keeps the usual data directory" \
    "$([[ "$RUN_OUT" != *"--user-data-dir"* && -d "$RUN_HOME/.local/share/code-server/User" ]] && echo true || echo false)" "$RUN_OUT"

# --- beside another: its own data directory, and its own settings -----------
run_launcher STUB_OTHER_CODESERVER=1
check "beside another code-server, it gets its own data directory" \
    "$([[ "$RUN_OUT" == *"--user-data-dir $RUN_HOME/.local/share/code-server-$port"* ]] && echo true || echo false)" "$RUN_OUT"
check "…writes its settings there, not into the running one's" \
    "$([[ -f "$RUN_HOME/.local/share/code-server-$port/User/settings.json" && ! -e "$RUN_HOME/.local/share/code-server/User/settings.json" ]] && echo true || echo false)" \
    "$(find "$RUN_HOME/.local/share" -name settings.json)"

# --- refusals -----------------------------------------------------------------
busy=$(free_port)
python3 -c "import socket,time;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',$busy));s.listen();time.sleep(30)" &
LISTENER=$!
for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$busy") 2>/dev/null && break; sleep 0.1; done
LAUNCH_ARGS=("$busy")
run_launcher
kill "$LISTENER" 2>/dev/null || true
check "a port already in use is refused, naming the way out" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"already in use"* && "$RUN_OUT" == *"start-codeserver <port>"* && "$RUN_OUT" != *"code-server --"* ]] && echo true || echo false)" "$RUN_OUT"

LAUNCH_ARGS=(notaport)
run_launcher
check "a bad port is refused with a usage line" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"Usage: start-codeserver [port]"* ]] && echo true || echo false)" "$RUN_OUT"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
