#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test 002: Maven build and execution test.
# Verifies that maven builds and runs the project correctly inside the container.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTH="$SCRIPT_DIR/../../../coding-booth"

echo "=== Test 002: Maven Build and Run ==="
echo ""

# Run maven build inside the container
echo "Running maven build inside container..."
output=$("$BOOTH" --silence-build -- './run-on-container.sh' 2>&1)

echo "$output"
echo ""

# Validate output contains expected patterns
failed=0

# Check for successful build/execution output
# The maven project should output something - check for common patterns
if echo "$output" | grep -qE "(Hello|BUILD SUCCESS|java|Java)"; then
    echo -e "${GREEN}✓${NC} Maven execution produced output"
else
    echo -e "${RED}✗${NC} Maven execution failed or no output"
    failed=1
fi

# Check that there are no build errors
if echo "$output" | grep -q "BUILD FAILURE"; then
    echo -e "${RED}✗${NC} Maven build failed"
    failed=1
else
    echo -e "${GREEN}✓${NC} No build failures detected"
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All Maven build and run checks passed!${NC}"
else
    echo -e "${RED}Maven build and run checks FAILED!${NC}"
    exit 1
fi
