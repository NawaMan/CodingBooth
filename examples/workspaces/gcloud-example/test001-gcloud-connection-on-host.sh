#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for gcloud example.
# Skips gracefully if gcloud credentials are not configured.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Testing gcloud Connection ==="
echo ""

# First check if gcloud credentials are available on the host
echo "Checking for gcloud credentials on host..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}⚠${NC} gcloud credentials not configured on host"
    echo -e "${YELLOW}⚠${NC} Skipping gcloud connection tests"
    echo ""
    echo -e "${YELLOW}Test skipped (no gcloud credentials)${NC}"
    exit 0
fi

echo -e "${GREEN}✓${NC} gcloud credentials found on host"
echo ""

# Test 1: gcloud connection on host
echo "Testing gcloud connection on host..."
if ./check-connection.sh; then
    echo -e "${GREEN}✓${NC} Host gcloud connection test passed"
else
    echo -e "${RED}✗${NC} Host gcloud connection test failed"
    exit 1
fi
echo ""

# Test 2: gcloud connection from inside the container
echo "Testing gcloud connection from inside container..."
if ../../../coding-booth --variant base --silence-build -- ./check-connection.sh; then
    echo -e "${GREEN}✓${NC} Container gcloud connection test passed"
else
    echo -e "${RED}✗${NC} Container gcloud connection test failed"
    exit 1
fi
echo ""

echo -e "${GREEN}All gcloud connection tests passed!${NC}"
