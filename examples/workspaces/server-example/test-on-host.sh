#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Tests the HTTP server accessibility from the host.
# Starts booth in daemon mode, tests port 8080, then stops booth.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="server-example"
SERVER_PORT=8080

cleanup() {
    echo
    echo "Cleaning up..."
    # Stop server if running
    docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./stop-server.sh" 2>/dev/null || true
    # Stop and remove the booth container
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Testing HTTP server from host ==="
echo

# Test 1: Start booth in daemon mode
echo "Starting coding-booth in daemon mode..."
../../../coding-booth --daemon > /dev/null 2>&1 || true
sleep 2

# Check if booth container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

# Test 2: Start server inside container
echo "Starting server inside container..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./start-server.sh > /dev/null 2>&1 &"
sleep 2

# Test 3: Verify server is accessible from host
echo "Checking server accessible from host on port ${SERVER_PORT}..."
if curl -s --max-time 5 "http://localhost:${SERVER_PORT}" | grep -q "Hello"; then
    pass "Server accessible from host"
else
    fail "Server should be accessible from host"
fi

# Test 4: Stop the booth container
echo "Stopping booth..."
docker stop "$CONTAINER_NAME" > /dev/null 2>&1
sleep 1

# Test 5: Verify server is NOT accessible after booth stops
echo "Checking server not accessible after booth stop..."
if curl -s --max-time 2 "http://localhost:${SERVER_PORT}" >/dev/null 2>&1; then
    fail "Server should not be accessible after booth stop"
else
    pass "Server not accessible (expected)"
fi

echo
echo -e "${GREEN}All host tests passed!${NC}"
