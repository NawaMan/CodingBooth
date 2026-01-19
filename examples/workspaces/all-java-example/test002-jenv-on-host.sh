#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test that jenv is properly installed and configured
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTH="$SCRIPT_DIR/../../../coding-booth"

echo "=== Testing jenv Installation ==="
echo ""

failed=0

# Test 1: jenv versions runs successfully
echo "Testing 'jenv versions'..."
if output=$("$BOOTH" --variant base -- 'jenv versions' 2>&1); then
    echo "$output"
    echo ""
    echo -e "${GREEN}✓${NC} 'jenv versions' completed successfully"
else
    echo -e "${RED}✗${NC} 'jenv versions' failed"
    failed=1
fi
echo ""

# Test 2: jenv version returns current version
echo "Testing 'jenv version'..."
if version_output=$("$BOOTH" --variant base -- 'jenv version' 2>&1); then
    echo "$version_output"
    # Check that output contains a version number pattern (e.g., "25" or "25.0.1")
    if echo "$version_output" | grep -qE '[0-9]+(\.[0-9]+)?'; then
        echo -e "${GREEN}✓${NC} 'jenv version' returned a valid version"
    else
        echo -e "${RED}✗${NC} 'jenv version' output doesn't contain a version number"
        failed=1
    fi
else
    echo -e "${RED}✗${NC} 'jenv version' failed"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All jenv checks passed!${NC}"
else
    echo -e "${RED}jenv checks FAILED!${NC}"
    exit 1
fi
