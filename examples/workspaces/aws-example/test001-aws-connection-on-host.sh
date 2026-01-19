#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for AWS example.
# Skips gracefully if AWS credentials are not configured.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Testing AWS Connection ==="
echo ""

# First check if AWS credentials are available on the host
echo "Checking for AWS credentials on host..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠${NC} AWS credentials not configured on host"
    echo -e "${YELLOW}⚠${NC} Skipping AWS connection tests"
    echo ""
    echo -e "${YELLOW}Test skipped (no AWS credentials)${NC}"
    exit 0
fi

echo -e "${GREEN}✓${NC} AWS credentials found on host"
echo ""

# Test 1: AWS connection on host
echo "Testing AWS connection on host..."
if ./check-connection.sh; then
    echo -e "${GREEN}✓${NC} Host AWS connection test passed"
else
    echo -e "${RED}✗${NC} Host AWS connection test failed"
    exit 1
fi
echo ""

# Test 2: AWS connection from inside the container
echo "Testing AWS connection from inside container..."
if ../../../coding-booth --variant base --silence-build -- ./check-connection.sh; then
    echo -e "${GREEN}✓${NC} Container AWS connection test passed"
else
    echo -e "${RED}✗${NC} Container AWS connection test failed"
    exit 1
fi
echo ""

echo -e "${GREEN}All AWS connection tests passed!${NC}"