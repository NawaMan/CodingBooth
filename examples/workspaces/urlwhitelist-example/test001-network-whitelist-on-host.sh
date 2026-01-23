#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Full integration test run from the host.
# Starts the workspace, runs container tests for network whitelist.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="urlwhitelist-example"

cleanup() {
    echo
    echo "Cleaning up..."
    # Stop booth
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Network Whitelist Test (on host) ==="
echo

# Start booth in daemon mode
echo "Starting coding-booth..."
../../../coding-booth --daemon > /dev/null 2>&1 || true

# Wait for booth to be ready
sleep 3

# Check if booth container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

# Run container tests
echo
echo "Running container tests..."
if docker exec "$CONTAINER_NAME" bash -lc "cd /home/coder/code && ./test-on-container.sh"; then
    pass "Container tests passed"
else
    fail "Container tests failed"
fi

echo
echo -e "${GREEN}All tests passed!${NC}"
