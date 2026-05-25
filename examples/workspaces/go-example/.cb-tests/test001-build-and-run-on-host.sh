#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for Go example.
# Verifies that the Go project builds, runs correctly, and all tools work.
# Combines build/run test with inBooth tests in a single container session.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
if [ -x "$REPO_ROOT/codingbooth" ]; then
    BOOTH="$REPO_ROOT/codingbooth"
else
    BOOTH="$REPO_ROOT/booth"
fi

echo "=== Testing Go Build, Run, and Tools ==="
echo ""

# Run build, run, and inBooth tests all in one container session
echo "Building, running treemoji, and testing Go tools inside container..."
output=$("$BOOTH" --variant base --port "${CB_PORT:-50121}" -- './build.sh && ./run-treemoji.sh && ./.cb-tests/inBooth--run-all-tests.sh' 2>&1)

echo "$output"
echo ""

# Validate output contains expected patterns
failed=0

# Check for build success message
if grep -q "Built:" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Build completed successfully"
else
    echo -e "${RED}✗${NC} Build failed or missing output"
    failed=1
fi

# Check for tree output (the emoji tree structure)
if grep -q "📁" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Found directory emoji in output"
else
    echo -e "${RED}✗${NC} Missing directory emoji in output"
    failed=1
fi

if grep -q "📄" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Found file emoji in output"
else
    echo -e "${RED}✗${NC} Missing file emoji in output"
    failed=1
fi

# Check for tree structure characters
if grep -q "├─\|└─" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Found tree structure in output"
else
    echo -e "${RED}✗${NC} Missing tree structure in output"
    failed=1
fi

# Check for inBooth tests passed
if grep -q "All tests passed!" <<< "$output"; then
    echo -e "${GREEN}✓${NC} All inBooth Go tool tests passed"
else
    echo -e "${RED}✗${NC} Some inBooth Go tool tests failed"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All Go checks passed!${NC}"
else
    echo -e "${RED}Go checks FAILED!${NC}"
    exit 1
fi
