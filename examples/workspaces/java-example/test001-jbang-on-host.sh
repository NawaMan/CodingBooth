#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test 001: JBang execution test.
# Verifies that jbang runs correctly inside the container.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTH="$SCRIPT_DIR/../../../coding-booth"

echo "=== Test 001: JBang Execution ==="
echo ""

# Run jbang inside the container
echo "Running jbang inside container from host..."
output=$(./run-example-on-host.sh 2>&1)

echo "$output"
echo ""

# Validate output contains expected patterns
failed=0

# Check for JDK version
if echo "$output" | grep -q "🚀 JDK:"; then
    echo -e "${GREEN}✓${NC} Found JDK version in output"
else
    echo -e "${RED}✗${NC} Missing JDK version in output"
    failed=1
fi

# Check for current working directory
if echo "$output" | grep -q "📁 CWD:"; then
    echo -e "${GREEN}✓${NC} Found CWD in output"
else
    echo -e "${RED}✗${NC} Missing CWD in output"
    failed=1
fi

# Check for args display
if echo "$output" | grep -q "🔧 Args:"; then
    echo -e "${GREEN}✓${NC} Found Args in output"
else
    echo -e "${RED}✗${NC} Missing Args in output"
    failed=1
fi

# Check for line output (args iteration)
if echo "$output" | grep -q "line 0:"; then
    echo -e "${GREEN}✓${NC} Found arg iteration output"
else
    echo -e "${RED}✗${NC} Missing arg iteration output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All JBang execution checks passed!${NC}"
else
    echo -e "${RED}JBang execution checks FAILED!${NC}"
    exit 1
fi
