#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Starts the i3-desktop-example booth and proves the desktop really tiles:
# i3 is the running window manager at login (xfwm4 and xfdesktop are not), the
# Ctrl+Alt twins are loaded, and stop-i3 / start-i3 switch a live session back
# to xfwm4 (with its desktop icons) and to i3 again.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)" || { echo "no booth found under $REPO_ROOT" >&2; exit 1; }

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="i3-desktop-example"

cleanup() {
    echo
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Run a command in the booth as coder, on the desktop's display.
in_booth() { docker exec -u coder -e DISPLAY=:1 "$CONTAINER_NAME" bash -lc "$1"; }
running()  { docker exec "$CONTAINER_NAME" pgrep -x "$1" >/dev/null 2>&1; }

# Poll up to $2 seconds for process $1 to be running (or, with "!", gone).
wait_for() {
    local want="$1" secs="$2" neg=0
    [[ "$want" == "!"* ]] && { neg=1; want="${want#!}"; }
    for _ in $(seq 1 "$secs"); do
        if running "$want"; then [[ $neg -eq 0 ]] && return 0
        else [[ $neg -eq 1 ]] && return 0
        fi
        sleep 1
    done
    return 1
}

echo "=== Testing i3-desktop-example ==="
echo

docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
sleep 1

echo "Starting codingbooth (XFCE desktop + i3)..."
"$BOOTH" --no-browser --port "${CB_PORT:-50741}" --daemon --name "$CONTAINER_NAME" || true

if grep -q "^${CONTAINER_NAME}$" <<< "$(docker ps --format '{{.Names}}')"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

echo "Waiting for the desktop session..."
wait_for xfce4-panel 90 && pass "XFCE panel is up" || fail "XFCE panel did not start within 90s"

wait_for i3 20 && pass "i3 is the window manager at login" || fail "i3 is not running"
running xfwm4     && fail "xfwm4 is running alongside i3" || pass "xfwm4 is not running"
running xfdesktop && fail "xfdesktop is running under i3" || pass "xfdesktop is not running"

if in_booth 'i3-msg -t get_config' | grep -q 'include /etc/xdg/i3/config.d'; then
    pass "i3 loaded /etc/xdg/i3/config"
else
    fail "i3 is not using /etc/xdg/i3/config"
fi
if docker exec "$CONTAINER_NAME" pgrep -f i3-config-wizard >/dev/null 2>&1; then
    fail "i3 fell back to the package config (i3-config-wizard is running)"
else
    pass "No i3 first-run wizard"
fi
if docker exec "$CONTAINER_NAME" grep -q '^bindsym Control+Mod1+h focus left$' /etc/xdg/i3/config.d/ctrl-alt.conf; then
    pass "Ctrl+Alt twins installed"
else
    fail "Ctrl+Alt twins missing"
fi

echo
echo "Switching back with stop-i3..."
in_booth 'stop-i3' || true
wait_for '!i3' 15    && pass "i3 exited"            || fail "i3 is still running after stop-i3"
wait_for xfwm4 15    && pass "xfwm4 took over"      || fail "xfwm4 did not start"
wait_for xfdesktop 15 && pass "desktop icons are back" || fail "xfdesktop did not start"

echo
echo "Tiling again with start-i3..."
in_booth 'start-i3' || true
wait_for i3 15        && pass "i3 is back"                   || fail "i3 did not start"
wait_for '!xfwm4' 15  && pass "xfwm4 stepped aside"          || fail "xfwm4 is still running"
wait_for '!xfdesktop' 15 && pass "xfdesktop is off under i3" || fail "xfdesktop is still running"

echo
echo -e "${GREEN}All tests passed!${NC}"
# cleanup() will be called automatically by the EXIT trap
