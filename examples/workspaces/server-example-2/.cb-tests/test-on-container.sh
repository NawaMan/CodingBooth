#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Tests the HTTP server inside the workspace container.
# Run this script from inside the container.

set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

SERVER_PORT=8080

cleanup() {
    ./stop-server.sh 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Testing HTTP server inside container ==="
echo

# Test 1: Verify server is NOT running initially
echo "Checking server is not running..."
if curl -s --max-time 5 "http://localhost:${SERVER_PORT}" >/dev/null 2>&1; then
    fail "Server should not be running initially"
else
    pass "Server not running (expected)"
fi

# Test 2: Start the server in background
echo "Starting server..."
./start-server.sh > /tmp/server.log 2>&1 &
SERVER_PID=$!
echo "  Server start PID: $SERVER_PID"

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
        echo "  Server did not start within ${MAX_RETRIES}s"
    else
        sleep $RETRY_DELAY
    fi
done

# Test 3: Verify server IS running
echo "Checking server is running..."
RESPONSE=$(curl -s --max-time 5 "http://localhost:${SERVER_PORT}" 2>&1 || true)
if echo "$RESPONSE" | grep -q "Hello"; then
    pass "Server is running and responding"
else
    echo "  Response: ${RESPONSE:-<empty>}"
    echo "  Server log:"
    cat /tmp/server.log 2>/dev/null | head -20 || echo "    <no log>"
    echo "  Process check:"
    ps aux | grep -E "python.*http.server" | grep -v grep || echo "    <no python server process>"
    echo "  Port check:"
    python3 -c "import socket; s=socket.socket(); s.settimeout(1); exit(0 if s.connect_ex(('localhost', ${SERVER_PORT})) == 0 else 1)" 2>/dev/null && echo "    port ${SERVER_PORT} is listening" || echo "    <port ${SERVER_PORT} not listening>"
    fail "Server should be running and responding"
fi

# Test 4: Stop the server
echo "Stopping server..."
./stop-server.sh
sleep 1

# Test 5: Verify server is NOT running after stop
echo "Checking server stopped..."
if curl -s --max-time 5 "http://localhost:${SERVER_PORT}" >/dev/null 2>&1; then
    fail "Server should not be running after stop"
else
    pass "Server stopped (expected)"
fi

echo
echo -e "${GREEN}All container tests passed!${NC}"
