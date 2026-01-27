#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for Firebase example.
# Skips gracefully if Firebase credentials are not configured.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Testing Firebase Connection ==="
echo ""

# First check if Firebase credentials are available on the host
echo "Checking for Firebase credentials on host..."
if ! firebase login:list 2>&1 | grep -q "Logged in as"; then
    echo -e "${YELLOW}⚠${NC} Firebase credentials not configured on host"
    echo -e "${YELLOW}⚠${NC} Skipping Firebase connection tests"
    echo ""
    echo -e "${YELLOW}Test skipped (no Firebase credentials)${NC}"
    exit 0
fi

echo -e "${GREEN}✓${NC} Firebase credentials found on host"
echo ""

# Test 1: Firebase connection on host
echo "Testing Firebase connection on host..."
if ./check-connection.sh; then
    echo -e "${GREEN}✓${NC} Host Firebase connection test passed"
else
    echo -e "${RED}✗${NC} Host Firebase connection test failed"
    exit 1
fi
echo ""

# Test 2: Firebase connection from inside the container
echo "Testing Firebase connection from inside container..."
if ../../../coding-booth --variant base --silence-build -- ./check-connection.sh; then
    echo -e "${GREEN}✓${NC} Container Firebase connection test passed"
else
    echo -e "${RED}✗${NC} Container Firebase connection test failed"
    exit 1
fi
echo ""

echo -e "${GREEN}All Firebase connection tests passed!${NC}"
