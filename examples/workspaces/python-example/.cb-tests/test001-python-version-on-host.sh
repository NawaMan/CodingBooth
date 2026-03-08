#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test that Python is properly installed and returns expected version (3.12)
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

echo "=== Testing Python Version (default 3.13) ==="
echo ""

# Capture python --version output
output=$("$BOOTH" --variant base --port "${CB_PORT:-50251}" -- 'python --version' 2>&1)

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
    echo -e "${GREEN}Python version check passed!${NC}"
else
    echo -e "${RED}Python version check FAILED!${NC}"
    exit 1
fi
