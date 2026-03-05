#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for npm-deps example.
# Verifies that npm packages from package.json are installed and working correctly.
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

echo "=== Test 001: NPM Dependencies from package.json ==="
echo ""

failed=0

# Test chalk package
echo "Testing chalk package..."
output=$("$BOOTH" --variant base --port 30200 -- 'node -e "require('"'"'chalk'"'"'); console.log('"'"'OK'"'"')"' 2>&1)
if echo "$output" | grep -q "OK"; then
    echo -e "${GREEN}✓${NC} chalk package is installed and requireable"
else
    echo -e "${RED}✗${NC} chalk package failed to require"
    echo "$output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All npm dependency tests passed!${NC}"
else
    echo -e "${RED}Some npm dependency tests FAILED!${NC}"
    exit 1
fi
