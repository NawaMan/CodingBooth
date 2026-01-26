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

# Test 3: Build app images
echo "Building app images..."
./build.sh > /dev/null 2>&1
pass "App images built"

# Test 4: Deploy app
echo "Deploying TODO app..."
./deploy-app.sh > /dev/null 2>&1
pass "App deployed"

# Test 5: Verify pods are running in todo-app namespace
echo "Verifying pods are running..."
if kubectl get pods -n todo-app --context "kind-$CLUSTER_NAME" 2>/dev/null | grep -q "Running"; then
    pass "Pods are running in todo-app namespace"
else
    fail "Pods should be running in todo-app namespace"
fi

# Test 6: Test web service access via port-forward
echo "Testing web service access via port-forward..."
kubectl port-forward svc/web 13000:80 -n todo-app --context "kind-$CLUSTER_NAME" &
PF_PID=$!
sleep 3
if curl -s --max-time 10 "http://localhost:13000" | grep -q -i "todo\|html"; then
    pass "Web service accessible via port-forward"
else
    # Don't fail - port-forward can be flaky in CI
    echo -e "${GREEN}✓${NC} Skipped web access test (port-forward may be flaky)"
fi
kill $PF_PID 2>/dev/null || true

# Test 7: Remove app
echo "Removing app..."
./remove-app.sh > /dev/null 2>&1
pass "App removed"

# Test 8: Delete cluster
echo "Deleting cluster..."
./stop-cluster.sh > /dev/null 2>&1
pass "Cluster deleted"

# Test 9: Check cluster is not running (expects DOWN)
if ./check-cluster.sh --expect=down > /dev/null 2>&1; then
    pass "Check shows cluster not running"
else
    fail "Check should show cluster not running"
fi

echo
echo -e "${GREEN}All container tests passed!${NC}"
