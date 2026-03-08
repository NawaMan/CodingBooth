#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for pip-deps example.
# Verifies that pip packages from requirements.txt are installed and working correctly.
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

echo "=== Test 001: Pip Dependencies from requirements.txt ==="
echo ""

failed=0

# Test requests package
echo "Testing requests package..."
output=$("$BOOTH" --variant base --port "${CB_PORT:-50232}" -- 'python3 -c "import requests; print('"'"'OK'"'"')"' 2>&1)
if echo "$output" | grep -q "OK"; then
    echo -e "${GREEN}✓${NC} requests package is installed and importable"
else
    echo -e "${RED}✗${NC} requests package failed to import"
    echo "$output"
    failed=1
fi

# Test flask package
echo "Testing flask package..."
output=$("$BOOTH" --variant base --port "${CB_PORT:-50232}" -- 'python3 -c "import flask; print('"'"'OK'"'"')"' 2>&1)
if echo "$output" | grep -q "OK"; then
    echo -e "${GREEN}✓${NC} flask package is installed and importable"
else
    echo -e "${RED}✗${NC} flask package failed to import"
    echo "$output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All pip dependency tests passed!${NC}"
else
    echo -e "${RED}Some pip dependency tests FAILED!${NC}"
    exit 1
fi
