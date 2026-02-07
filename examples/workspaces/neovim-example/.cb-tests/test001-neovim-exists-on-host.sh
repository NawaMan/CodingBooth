#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test that Neovim is properly installed
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

echo "=== Testing Neovim Exists ==="
echo ""

# Capture nvim --version output
output=$("$BOOTH" --variant base --port 27000 -- 'nvim --version' 2>&1)

echo "$output"
echo ""

# Validate output contains expected pattern
failed=0

if echo "$output" | grep -q "NVIM"; then
    echo -e "${GREEN}✓${NC} Found 'NVIM'"
else
    echo -e "${RED}✗${NC} Expected 'NVIM' in output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Neovim check passed!${NC}"
else
    echo -e "${RED}Neovim check FAILED!${NC}"
    exit 1
fi
