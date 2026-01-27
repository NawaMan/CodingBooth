#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Tests JavaScript runtime installations and start/check/stop scripts inside the workspace container.
# Run this script from inside the container.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
skip() { echo -e "${YELLOW}○${NC} $1 (not installed)"; }

echo "=== Testing inside container ==="
echo

# Track which runtimes are available
HAS_NODE=false
HAS_BUN=false
HAS_DENO=false

# Test Node.js
echo "Checking Node.js installation..."
if node --version > /dev/null 2>&1; then
    NODE_VERSION=$(node --version)
    pass "Node.js installed: $NODE_VERSION"
    HAS_NODE=true

    # Check npm
    if npm --version > /dev/null 2>&1; then
        NPM_VERSION=$(npm --version)
        pass "npm installed: $NPM_VERSION"
    else
        fail "npm not installed (required with Node.js)"
    fi
else
    skip "Node.js"
fi

# Test Bun
echo "Checking Bun installation..."
if bun --version > /dev/null 2>&1; then
    BUN_VERSION=$(bun --version)
    pass "Bun installed: $BUN_VERSION"
    HAS_BUN=true
else
    skip "Bun"
fi

# Test Deno
echo "Checking Deno installation..."
if deno --version > /dev/null 2>&1; then
    DENO_VERSION=$(deno --version | head -1)
    pass "Deno installed: $DENO_VERSION"
    HAS_DENO=true
else
    skip "Deno"
fi

# Ensure at least one runtime is available
if [[ "$HAS_NODE" == "false" && "$HAS_BUN" == "false" && "$HAS_DENO" == "false" ]]; then
    fail "No JavaScript runtime installed (need at least one of: node, bun, deno)"
fi

echo
echo "=== Testing server with each runtime ==="
echo

API_PORT=${API_PORT:-3000}

# Helper function to test a runtime
test_runtime() {
    local runtime="$1"
    local start_cmd="$2"

    echo "Testing server with ${runtime}..."

    # Start server
    eval "$start_cmd" > /dev/null 2>&1
    sleep 2

    # Check it's running
    if ./check-server.sh --expect=up > /dev/null 2>&1; then
        pass "${runtime}: Server started"
    else
        fail "${runtime}: Server failed to start"
    fi

    # Test HTTP response - API returns JSON with 'iso' field from /api/time
    if curl -s --max-time 5 "http://localhost:${API_PORT}/api/time" | grep -q "iso"; then
        pass "${runtime}: Server responds to HTTP"
    else
        fail "${runtime}: Server should respond to HTTP"
    fi

    # Stop server
    ./stop-server.sh > /dev/null 2>&1
    sleep 0.5

    # Check it stopped
    if ./check-server.sh --expect=down > /dev/null 2>&1; then
        pass "${runtime}: Server stopped"
    else
        fail "${runtime}: Server should have stopped"
    fi

    echo
}

# Test with Node.js
if [[ "$HAS_NODE" == "true" ]]; then
    test_runtime "Node.js" "./start-server.sh --runtime=node"
fi

# Test with Bun
if [[ "$HAS_BUN" == "true" ]]; then
    test_runtime "Bun" "./start-server.sh --runtime=bun"
fi

# Test with Deno
if [[ "$HAS_DENO" == "true" ]]; then
    test_runtime "Deno" "./start-server.sh --runtime=deno"
fi

echo -e "${GREEN}All container tests passed!${NC}"
