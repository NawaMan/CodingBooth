#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Tests the start/check/stop scripts inside the workspace container.
# Run this script from inside the container.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "=== Testing inside container ==="
echo

# Test 1: Start server
echo "Starting server..."
./start-server.sh > /dev/null 2>&1
pass "Server started"

# Test 2: Check server is running
if ./check-server.sh 2>/dev/null | grep -q "✓"; then
    pass "Check shows server running"
else
    fail "Check should show server running"
fi

# Test 3: Stop server
echo "Stopping server..."
./stop-server.sh > /dev/null 2>&1
pass "Server stopped"

# Test 4: Check server is not running
if ./check-server.sh 2>/dev/null | grep -q "✗"; then
    pass "Check shows server not running"
else
    fail "Check should show server not running"
fi

echo
echo -e "${GREEN}All container tests passed!${NC}"
