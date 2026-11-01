#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Start the booth as a daemon and run the in-booth suite with docker exec.
# `booth -- <cmd>` runs the command without starting the desktop, and test004
# launches the app's window on DISPLAY=:1, so the booth has to be a full one.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)" || { echo "no booth found under $REPO_ROOT" >&2; exit 1; }

cd "$(dirname "$0")/.."

export CB_BROWSER=false

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

CONTAINER_NAME="wails-example"
BOOTH_PORT="${CB_PORT:-50422}"

# booth stop/remove also take down the DinD sidecar that dind = true brings.
cleanup() {
    echo
    echo "Cleaning up..."
    "$BOOTH" stop --name "$CONTAINER_NAME" --force >/dev/null 2>&1 || true
    "$BOOTH" remove --name "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker network rm "${CONTAINER_NAME}-${BOOTH_PORT}-net" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Testing wails-example ==="
cleanup

# --dind-allowed: this example's dind = true would otherwise stop for a [y/N]
# consent prompt on /dev/tty (see docs/BOOTH_SECURITY.md) — silent in a script.
"$BOOTH" --dind-allowed --no-browser --port "$BOOTH_PORT" --daemon --name "$CONTAINER_NAME" || true
sleep 2
grep -q "^${CONTAINER_NAME}$" <<< "$(docker ps --format '{{.Names}}')" || fail "Failed to start booth"
pass "Booth started"

echo
echo "Running in-booth tests..."
if ! docker exec -u coder "$CONTAINER_NAME" bash -lc "cd /home/coder/code && ./.cb-tests/inBooth--run-all-tests.sh" 2>&1 | tee "$0.out"; then
    fail "In-booth tests failed"
fi
# A run that produced no summary did not run the suite, whatever it exited with.
grep -q "TEST SUMMARY" "$0.out" || fail "The in-booth test suite produced no summary — it did not run (see $0.out)"
pass "In-booth tests passed"

echo
echo -e "${GREEN}All tests passed!${NC}"
