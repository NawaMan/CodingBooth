#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test 001: Run container tests inside the workspace.
# Starts the workspace, runs test-on-container.sh, then cleans up.

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
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm   "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Test 001: Container Tests ==="
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

echo
echo -e "${GREEN}All container tests passed!${NC}"
