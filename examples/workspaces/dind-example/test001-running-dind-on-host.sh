#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Full integration test run from the host.
# Starts the workspace, runs container tests, and verifies host port accessibility.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="dind-example"
SERVER_PORT=8080

cleanup() {
    echo
    echo "Cleaning up..."
    # Stop http-server if running
    docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./stop-server.sh" 2>/dev/null || true
    # Stop workspace
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker stop "${CONTAINER_NAME}-10000-dind" 2>/dev/null || true
    docker network rm "${CONTAINER_NAME}-10000-net" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Testing on host ==="
echo

# Start workspace in daemon mode
echo "Starting workspace..."
../../../coding-booth --daemon > /dev/null 2>&1 || true

# Wait for workspace to be ready
sleep 2

# Check if workspace container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    pass "Workspace started"
else
    fail "Failed to start workspace"
fi

# Run container tests
echo
echo "Running container tests..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./test-on-container.sh"
pass "Container tests passed"

# Test host accessibility
echo
echo "=== Testing host accessibility ==="
echo

# Start server for host tests
echo "Starting server for host tests..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./start-server.sh" > /dev/null 2>&1
pass "Server started"

# Wait for server to be ready
sleep 1

# Test curl from host
echo "Testing curl from host..."
if curl -s --max-time 5 "http://localhost:${SERVER_PORT}" | grep -q "Hello"; then
    pass "Server accessible from host at port ${SERVER_PORT}"
else
    fail "Server should be accessible from host"
fi

# Stop server
echo "Stopping server..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./stop-server.sh" > /dev/null 2>&1
pass "Server stopped"

# Wait for port to close
sleep 1

# Test curl fails from host
echo "Testing curl fails after stop..."
if curl -s --max-time 2 "http://localhost:${SERVER_PORT}" 2>/dev/null | grep -q "Hello"; then
    fail "Server should not be accessible after stop"
else
    pass "Server not accessible from host (expected)"
fi

# Stop and remove container
echo "Stopping and removing container..."
docker stop "$CONTAINER_NAME" || true
docker rm   "$CONTAINER_NAME" || true

echo
echo -e "${GREEN}All tests passed!${NC}"
