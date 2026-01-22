#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Tests the KinD cluster scripts inside the workspace container.
# Run this script from inside the container.

set -euo pipefail

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

CLUSTER_NAME="kind"

echo "=== Testing KinD inside container ==="
echo

# Test 1: Create cluster
echo "Creating KinD cluster..."
./start-cluster.sh > /dev/null 2>&1
pass "Cluster created"

# Test 2: Check cluster is running (expects UP)
if ./check-cluster.sh --expect=up > /dev/null 2>&1; then
    pass "Check shows cluster running"
else
    fail "Check should show cluster running"
fi

# Test 3: Deploy app
echo "Deploying nginx app..."
./deploy-app.sh > /dev/null 2>&1
pass "App deployed"

# Test 4: Verify pods are running
if kubectl get pods --context "kind-$CLUSTER_NAME" 2>/dev/null | grep -q "Running"; then
    pass "Pods are running"
else
    fail "Pods should be running"
fi

# Test 5: Test NodePort access via localhost
echo "Testing NodePort access via localhost..."
sleep 2
if curl -s --max-time 10 "http://localhost:30080" | grep -q -i "nginx\|welcome"; then
    pass "NodePort accessible via localhost (http://localhost:30080)"
else
    fail "NodePort should be accessible via localhost"
fi

# Test 6: Remove app
echo "Removing app..."
./remove-app.sh > /dev/null 2>&1
pass "App removed"

# Test 7: Delete cluster
echo "Deleting cluster..."
./stop-cluster.sh > /dev/null 2>&1
pass "Cluster deleted"

# Test 8: Check cluster is not running (expects DOWN)
if ./check-cluster.sh --expect=down > /dev/null 2>&1; then
    pass "Check shows cluster not running"
else
    fail "Check should show cluster not running"
fi

echo
echo -e "${GREEN}All container tests passed!${NC}"
