#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Full integration test run from the host.
# Starts the workspace, runs container tests, and cleans up.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="nodejs-example"

cleanup() {
    echo
    echo "Cleaning up..."
    # Stop node server if running
    docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/workspace && ./stop-server.sh" 2>/dev/null || true
    # Stop workspace
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Testing on host ==="
echo

# Start workspace in daemon mode
echo "Starting workspace..."
../../workspace --keep-alive --daemon --silence-build > /dev/null 2>&1 || true

# Wait for workspace to be ready
sleep 3

# Check if workspace container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    pass "Workspace started"
else
    fail "Failed to start workspace"
fi

# Check Node.js version from host
echo
echo "Checking Node.js from host..."
NODE_VERSION=$(docker exec "$CONTAINER_NAME" node --version 2>/dev/null)
if [[ -n "$NODE_VERSION" ]]; then
    pass "Node.js accessible from host: $NODE_VERSION"
else
    fail "Node.js not accessible"
fi

# Check npm version from host
NPM_VERSION=$(docker exec "$CONTAINER_NAME" npm --version 2>/dev/null)
if [[ -n "$NPM_VERSION" ]]; then
    pass "npm accessible from host: $NPM_VERSION"
else
    fail "npm not accessible"
fi

# Run container tests
echo
echo "Running container tests..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/workspace && ./test-on-container.sh"
pass "Container tests passed"

echo
echo -e "${GREEN}All tests passed!${NC}"
