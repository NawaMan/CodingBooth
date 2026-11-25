#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test 001: Run container tests inside the workspace.
# Starts the workspace, runs test-on-container.sh, then cleans up.

set -euo pipefail

# Locate the booth to run from this script's own location, so it works from any cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)" || { echo "no booth found under $REPO_ROOT" >&2; exit 1; }

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="js-example"
CONTAINER_PORT=23080

cleanup() {
    echo
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm   "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Test 001: Container Tests ==="
echo

# Pre-cleanup: ensure no leftover container
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
# A --rm booth is removed asynchronously after it stops, so the name can still be taken
# for a moment. Wait until it is really gone: starting on a taken name fails.
for _ in $(seq 1 30); do
    docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1 || break
    sleep 1
done

# Start workspace in daemon mode
echo "Starting codingbooth..."
"$BOOTH" --no-browser --daemon --variant base --port "${CB_PORT:-50161}" --name "$CONTAINER_NAME" -p "$CONTAINER_PORT":8080 \
    || fail "booth failed to start"

# Wait for npm install to complete (up to 120 seconds)
echo "Waiting for npm install to complete..."
WAIT_COUNT=0
while true; do
    if grep -q "npm install completed" <<< "$(docker logs "$CONTAINER_NAME" 2>&1)"; then
        break
    fi
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ "$WAIT_COUNT" -ge 120 ]; then
        fail "Timeout waiting for npm install to complete"
    fi
    sleep 1
done
pass "npm install completed"

# Check if booth container is running
if grep -q "^${CONTAINER_NAME}$" <<< "$(docker ps --format '{{.Names}}')"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

# Run container tests
echo
echo "Running container tests..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./.cb-tests/test-on-container.sh"
pass "Container tests passed"

echo
echo -e "${GREEN}All container tests passed!${NC}"
