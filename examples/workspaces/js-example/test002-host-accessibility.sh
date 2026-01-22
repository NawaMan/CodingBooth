#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test 002: Verify host accessibility of container services.
# Starts workspace, starts server inside container, verifies ports accessible from host.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="js-example"

cleanup() {
    echo
    echo "Cleaning up..."
    # Stop servers if running
    docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./stop-server.sh" 2>/dev/null || true
    # Stop workspace
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm   "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Test 002: Host Accessibility ==="
echo

# Start workspace in daemon mode
echo "Starting workspace..."
../../../coding-booth --daemon > /dev/null 2>&1 || true

# Wait for npm install to complete (up to 60 seconds)
echo "Waiting for npm install to complete..."
WAIT_COUNT=0
while true; do
    if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "npm install completed"; then
        break
    fi
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ "$WAIT_COUNT" -ge 60 ]; then
        fail "Timeout waiting for npm install to complete"
    fi
    sleep 1
done
pass "npm install completed"

# Check if workspace container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    pass "Workspace started"
else
    fail "Failed to start workspace"
fi

# Start server inside container
echo
echo "Starting server inside container..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./start-server.sh" > /dev/null 2>&1
pass "Server started"

# Wait for server to be ready
sleep 2

# Check servers are accessible from host
echo "Checking servers from host..."
if ./check-server.sh --expect=up; then
    pass "Servers accessible from host"
else
    fail "Servers should be accessible from host"
fi

# Stop server
echo "Stopping server..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./stop-server.sh" > /dev/null 2>&1
pass "Server stopped"

# Wait for ports to close
sleep 1

# Check servers are down from host
echo "Checking servers are down from host..."
if ./check-server.sh --expect=down; then
    pass "Servers not accessible from host (expected)"
else
    fail "Servers should not be accessible after stop"
fi

echo
echo -e "${GREEN}All host accessibility tests passed!${NC}"
