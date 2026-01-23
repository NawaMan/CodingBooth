#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Full integration test run from the host.
# Starts the workspace, runs container tests.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; cleanup; exit 1; }

CONTAINER_NAME="kind-example"

cleanup() {
    echo
    echo "Cleaning up..."
    # Delete kind cluster if running
    docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./stop-cluster.sh" 2>/dev/null || true
    # Stop booth
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker stop "${CONTAINER_NAME}-10000-dind" 2>/dev/null || true
    docker network rm "${CONTAINER_NAME}-10000-net" 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Testing KinD example on host ==="
echo

# Start booth in daemon mode
echo "Starting booth with KinD..."
../../../coding-booth --keep-alive --daemon > /dev/null 2>&1 || true

# Wait for booth to be ready
sleep 3

# Check if booth container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    pass "Booth started"
else
    fail "Failed to start booth"
fi

# Check if DinD sidecar is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}-10000-dind$"; then
    pass "DinD sidecar running"
else
    fail "DinD sidecar should be running"
fi

# Run container tests
echo
echo "Running container tests..."
docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && ./test-on-container.sh"
pass "Container tests passed"

echo
echo -e "${GREEN}All tests passed!${NC}"
