#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test that Python version can be overridden via --build-arg PY_VERSION=3.13
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Testing Python Version Override (3.13 via --build-arg) ==="
echo ""

# Capture python --version output with build-arg override
output=$("$SCRIPT_DIR/../../../coding-booth" --variant base --silence-build --build-arg PY_VERSION=3.13 -- 'python --version' 2>&1)

echo "$output"
echo ""

# Validate output contains expected version
failed=0

if echo "$output" | grep -q "Python 3\.13"; then
    echo -e "${GREEN}✓${NC} Found 'Python 3.13'"
else
    echo -e "${RED}✗${NC} Expected 'Python 3.13' but got: $output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Python version override check passed!${NC}"
else
    echo -e "${RED}Python version override check FAILED!${NC}"
    exit 1
fi
