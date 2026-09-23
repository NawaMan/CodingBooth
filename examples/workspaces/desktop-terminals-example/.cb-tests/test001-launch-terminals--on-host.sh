#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Starts the desktop-terminals-example booth, waits for its Xvnc session, then
# actually launches Alacritty and Kitty inside it — proving they run (a working
# GL context under Xvnc), not just that the packages are on PATH.

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

CONTAINER_NAME="desktop-terminals-example"

cleanup() {
    echo
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Testing desktop-terminals-example ==="
echo

docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
sleep 1

echo "Starting codingbooth (XFCE desktop)..."
# No --variant here on purpose: the booth uses whatever .booth/config.toml
# declares (xfce), so the test exercises the environment the example actually
# ships rather than a lighter stand-in.
"$BOOTH" --no-browser --port "${CB_PORT:-50731}" --daemon --name "$CONTAINER_NAME" || true

if grep -q "^${CONTAINER_NAME}$" <<< "$(docker ps --format '{{.Names}}')"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

echo "Waiting for the desktop's VNC X server..."
# TigerVNC's actual process name is Xtigervnc, not Xvnc.
XVNC_UP=0
for i in $(seq 1 60); do
    if docker exec "$CONTAINER_NAME" pgrep -f 'Xtigervnc|Xvnc' >/dev/null 2>&1; then
        XVNC_UP=1
        break
    fi
    sleep 1
done
if [[ "$XVNC_UP" -eq 1 ]]; then
    pass "VNC X server is running"
else
    fail "VNC X server did not start within 60s"
fi

# Terminals need the X session's auth cookie, which lives in the "coder" user's
# home (~/.Xauthority) — exec as root (docker exec's default) hits
# "Authorization required, but no authorization protocol specified".
#
# Each terminal renders its child shell in its own pty/window rather than the
# outer docker-exec's stdout, so a file the child wrote — not captured
# output or the terminal's own exit code — is what proves the command
# actually ran inside it.
echo
echo "Launching Alacritty inside the booth..."
docker exec -u coder -e DISPLAY=:1 "$CONTAINER_NAME" timeout 10 alacritty -e sh -c 'echo ALACRITTY_OK > /tmp/alacritty-marker.txt' || true
if docker exec -u coder "$CONTAINER_NAME" bash -c 'sleep 1; cat /tmp/alacritty-marker.txt 2>/dev/null' | grep -q "ALACRITTY_OK"; then
    pass "Alacritty launched and ran a command in its pty"
else
    fail "Alacritty failed to launch"
fi

echo
echo "Launching Kitty inside the booth..."
docker exec -u coder -e DISPLAY=:1 "$CONTAINER_NAME" timeout 10 kitty sh -c 'echo KITTY_OK > /tmp/kitty-marker.txt' || true
if docker exec -u coder "$CONTAINER_NAME" bash -c 'sleep 1; cat /tmp/kitty-marker.txt 2>/dev/null' | grep -q "KITTY_OK"; then
    pass "Kitty launched and ran a command in its pty"
else
    fail "Kitty failed to launch"
fi

echo
echo "Checking seeded font configs..."
ALA_CONF=$(docker exec -u coder "$CONTAINER_NAME" bash -lc 'cat "$HOME/.config/alacritty/alacritty.toml" 2>/dev/null' || true)
if grep -q "FiraCode Nerd Font Mono" <<< "$ALA_CONF"; then
    pass "Alacritty config seeded with FiraCode Nerd Font Mono"
else
    fail "Alacritty config was not seeded"
fi

KITTY_CONF=$(docker exec -u coder "$CONTAINER_NAME" bash -lc 'cat "$HOME/.config/kitty/kitty.conf" 2>/dev/null' || true)
if grep -q "FiraCode Nerd Font Mono" <<< "$KITTY_CONF"; then
    pass "Kitty config seeded with FiraCode Nerd Font Mono"
else
    fail "Kitty config was not seeded"
fi

echo
echo -e "${GREEN}All tests passed!${NC}"
# cleanup() will be called automatically by the EXIT trap
