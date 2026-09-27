#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: booth--expose close
#
# A tunnel lives as long as its control file in .booth/.tmp/tcp-tunnels/ — the
# host-side booth process closes the listener once the file is gone — so close
# is the script's side of that contract: remove the file. Run on the host against
# a throwaway $HOME; the host-side watcher is covered by the live check, not here.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPOSE="$REPO_ROOT/variants/base/setups/booth--expose"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

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

# A fresh booth home per case: ~/code/.booth with an empty config.toml.
fresh_home() {
    HOME_DIR=$(mktemp -d "$WORK/home-XXXX")
    mkdir -p "$HOME_DIR/code/.booth"
    : > "$HOME_DIR/code/.booth/config.toml"
    TUNNELS="$HOME_DIR/code/.booth/.tmp/tcp-tunnels"
    CONFIG="$HOME_DIR/code/.booth/config.toml"
}

expose() {
    RUN_OUT=$(HOME="$HOME_DIR" BOOTH_HOST_PORT=10000 bash "$EXPOSE" "$@" 2>&1) && RUN_EXIT=0 || RUN_EXIT=$?
}

# --- open, then close ---------------------------------------------------------
fresh_home
expose 8080 18080
check "booth--expose 8080 18080 writes the control file" \
    "$([[ "$(cat "$TUNNELS/8080" 2>/dev/null)" == 18080 ]] && echo true || echo false)" "$RUN_OUT"

expose close 8080
check "close 8080 removes the control file" \
    "$([[ "$RUN_EXIT" == 0 && ! -e "$TUNNELS/8080" ]] && echo true || echo false)" "$RUN_OUT"
check "close 8080 says which mapping it closed" \
    "$([[ "$RUN_OUT" == *"container localhost:8080 -> host localhost:18080"* ]] && echo true || echo false)" "$RUN_OUT"

expose 8080
check "the port can be exposed again after close" \
    "$([[ "$RUN_EXIT" == 0 && -f "$TUNNELS/8080" ]] && echo true || echo false)" "$RUN_OUT"

expose 8080
check "exposing an open port points at close" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"booth--expose close 8080"* ]] && echo true || echo false)" "$RUN_OUT"

# --- only the named tunnel is closed -------------------------------------------
fresh_home
expose 8080
expose 9090
expose close 8080
check "close leaves other tunnels open" \
    "$([[ ! -e "$TUNNELS/8080" && -f "$TUNNELS/9090" ]] && echo true || echo false)" "$(ls "$TUNNELS")"

# --- errors ------------------------------------------------------------------
fresh_home
expose close 8080
check "close on a port with no tunnel fails and says so" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"no tunnel for container port 8080"* ]] && echo true || echo false)" "$RUN_OUT"

expose close
check "close with no port fails with the usage" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"booth--expose close <container-port>"* ]] && echo true || echo false)" "$RUN_OUT"

expose close notaport
check "close with a bad port fails" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"invalid container port"* ]] && echo true || echo false)" "$RUN_OUT"

# --- --permanent is gone: tunnels end with the booth -------------------------
fresh_home
expose 8080
expose close 8080 --permanent
check "close --permanent is refused, and the tunnel is left alone" \
    "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"--permanent was removed"* && -f "$TUNNELS/8080" ]] && echo true || echo false)" "$RUN_OUT"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
