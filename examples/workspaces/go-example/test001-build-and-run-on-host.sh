#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for Go example.
# Verifies that the Go project builds and runs correctly.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTH="$SCRIPT_DIR/../../../coding-booth"

echo "=== Testing Go Build and Run ==="
echo ""

# Run build and run inside the container
echo "Building and running treemoji inside container..."
output=$("$BOOTH" --silence-build -- './build.sh ; ./run.sh' 2>&1)

echo "$output"
echo ""

# Validate output contains expected patterns
failed=0

# Check for build success message
if echo "$output" | grep -q "Built:"; then
    echo -e "${GREEN}✓${NC} Build completed successfully"
else
    echo -e "${RED}✗${NC} Build failed or missing output"
    failed=1
fi

# Check for tree output (the emoji tree structure)
if echo "$output" | grep -q "📁"; then
    echo -e "${GREEN}✓${NC} Found directory emoji in output"
else
    echo -e "${RED}✗${NC} Missing directory emoji in output"
    failed=1
fi

if echo "$output" | grep -q "📄"; then
    echo -e "${GREEN}✓${NC} Found file emoji in output"
else
    echo -e "${RED}✗${NC} Missing file emoji in output"
    failed=1
fi

# Check for tree structure characters
if echo "$output" | grep -q "├─\|└─"; then
    echo -e "${GREEN}✓${NC} Found tree structure in output"
else
    echo -e "${RED}✗${NC} Missing tree structure in output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All Go build and run checks passed!${NC}"
else
    echo -e "${RED}Go build and run checks FAILED!${NC}"
    exit 1
fi
