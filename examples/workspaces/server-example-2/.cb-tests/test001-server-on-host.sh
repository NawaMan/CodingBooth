#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Full integration test run from the host.
# Starts the workspace, runs container tests, and verifies host port accessibility.

set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="server-example"
SERVER_HOST_PORT=34080

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

echo "=== Testing server-example ==="
echo

# Pre-cleanup: ensure no leftover container
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
sleep 1

# Start workspace in daemon mode with fixed port mapping
echo "Starting codingbooth..."
../../../codingbooth --no-browser --variant base --port "${CB_PORT:-50301}" --daemon --name "$CONTAINER_NAME" -p "$SERVER_HOST_PORT":8080 || true
sleep 2

# Check if booth container is running
if grep -q "^${CONTAINER_NAME}$" <<< "$(docker ps --format '{{.Names}}')"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

# Use the configured host port
SERVER_PORT=$SERVER_HOST_PORT
pass "Using host port: $SERVER_PORT"

# Run container tests
echo
echo "Running container tests..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./.cb-tests/test-on-container.sh"
pass "Container tests passed"

# Test host accessibility
echo
echo "=== Testing host accessibility ==="
echo

# Start server for host tests
echo "Starting server for host tests..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./start-server.sh > /tmp/server.log 2>&1 &"

# Wait for server to start with retries
MAX_RETRIES=10
RETRY_DELAY=1
echo "  Waiting for server to start (max ${MAX_RETRIES}s)..."

for i in $(seq 1 $MAX_RETRIES); do
    if curl -s --max-time 5 "http://localhost:${SERVER_PORT}" | grep -q "Hello"; then
        echo "  Server ready after ${i}s"
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo "  Server did not respond within ${MAX_RETRIES}s"
    else
        sleep $RETRY_DELAY
    fi
done

# Test curl from host
echo "Testing curl from host..."
RESPONSE=$(curl -s --max-time 5 "http://localhost:${SERVER_PORT}" 2>&1 || true)
if echo "$RESPONSE" | grep -q "Hello"; then
    pass "Server accessible from host at port ${SERVER_PORT}"
else
    echo "  Response: ${RESPONSE:-<empty>}"
    echo "  Container server log:"
    docker exec "$CONTAINER_NAME" cat /tmp/server.log 2>/dev/null | head -20 || echo "    <no log>"
    echo "  Container process check:"
    docker exec "$CONTAINER_NAME" ps aux 2>/dev/null | grep -E "python.*http.server" | grep -v grep || echo "    <no python server process>"
    echo "  Container port check:"
    docker exec "$CONTAINER_NAME" python3 -c "import socket; s=socket.socket(); s.settimeout(1); exit(0 if s.connect_ex(('localhost', 8080)) == 0 else 1)" 2>/dev/null && echo "    port 8080 is listening" || echo "    <port 8080 not listening>"
    echo "  Host port mapping check:"
    docker port "$CONTAINER_NAME" 2>/dev/null || echo "    <no port mappings>"
    fail "Server should be accessible from host"
fi

# Stop server
echo "Stopping server..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./stop-server.sh" > /dev/null 2>&1
sleep 1

# Test curl fails from host
echo "Testing curl fails after stop..."
if curl -s --max-time 5 "http://localhost:${SERVER_PORT}" 2>/dev/null | grep -q "Hello"; then
    fail "Server should not be accessible after stop"
else
    pass "Server not accessible from host (expected)"
fi

echo
echo -e "${GREEN}All tests passed!${NC}"
# cleanup() will be called automatically by the EXIT trap
