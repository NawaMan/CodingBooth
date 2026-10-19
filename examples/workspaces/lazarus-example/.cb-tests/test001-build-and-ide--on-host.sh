#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Starts the lazarus-example booth (XFCE), builds Prime Finder with lazbuild,
# runs it on the desktop's display with --self-test (the real .lfm form is
# loaded and its button pressed), and checks the Lazarus IDE is installed,
# on the desktop, and actually starts.

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

CONTAINER_NAME="lazarus-example"

cleanup() {
    echo
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

in_booth() { docker exec -u coder -e DISPLAY=:1 -w /home/coder/code "$CONTAINER_NAME" bash -lc "$1"; }

echo "=== Testing lazarus-example ==="
echo

docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
sleep 1

echo "Starting codingbooth (XFCE desktop)..."
# No --variant: the test runs the desktop the example ships, since the IDE is only installed there.
"$BOOTH" --no-browser --port "${CB_PORT:-50781}" --daemon --name "$CONTAINER_NAME" || true

if grep -q "^${CONTAINER_NAME}$" <<< "$(docker ps --format '{{.Names}}')"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

echo "Waiting for the desktop's VNC X server..."
XVNC_UP=0
for i in $(seq 1 60); do
    if docker exec "$CONTAINER_NAME" pgrep -f 'Xtigervnc|Xvnc' >/dev/null 2>&1; then
        XVNC_UP=1
        break
    fi
    sleep 1
done
[[ "$XVNC_UP" -eq 1 ]] && pass "VNC X server is running" || fail "VNC X server did not start within 60s"

echo
echo "Building and self-testing Prime Finder..."
OUT=$(in_booth 'just clean >/dev/null && just check 30' 2>&1 || true)
if grep -q "^Prime Finder: 2, 3, 5, 7, 11, 13, 17, 19, 23, 29$" <<< "$OUT" \
    && grep -q "^10 primes up to 30$" <<< "$OUT"; then
    pass "lazbuild built Prime Finder; its form found the primes up to 30"
else
    echo "$OUT" | tail -20 | sed 's/^/    /'
    fail "Prime Finder did not build or did not report the primes up to 30"
fi

echo
echo "Checking the Lazarus IDE..."
if in_booth 'command -v lazarus-ide >/dev/null && ls ~/Desktop | grep -q "^lazarus.*\.desktop$"'; then
    pass "Lazarus IDE installed, with a desktop icon"
else
    fail "Lazarus IDE or its desktop icon is missing"
fi

in_booth 'just ide' >/dev/null 2>&1 || true
sleep 15
if docker exec "$CONTAINER_NAME" pgrep -f '/usr/lib/lazarus/.*/lazarus ' >/dev/null 2>&1; then
    pass "Lazarus IDE started on the desktop"
else
    fail "Lazarus IDE did not start"
fi

echo
echo -e "${GREEN}All tests passed!${NC}"
