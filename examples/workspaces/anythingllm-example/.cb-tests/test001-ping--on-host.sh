#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for AnythingLLM example.
# Verifies the self-hosted UI answers /api/ping.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
if [ -x "$REPO_ROOT/codingbooth" ]; then
    BOOTH="$REPO_ROOT/codingbooth"
else
    BOOTH="$REPO_ROOT/booth"
fi

echo "=== Testing AnythingLLM /api/ping ==="
echo ""

# First boot copies the official AnythingLLM image — several minutes.
output=$("$BOOTH" --variant base --port "${CB_PORT:-50320}" -- 'just run' 2>&1) || true

echo "$output"
echo ""

failed=0

if grep -qi 'online\|AnythingLLM\|true' <<< "$output"; then
    echo -e "${GREEN}✓${NC} AnythingLLM /api/ping returned a body"
else
    echo -e "${RED}✗${NC} AnythingLLM /api/ping missing"
    failed=1
fi

if grep -q 'AnythingLLM is up' <<< "$output"; then
    echo -e "${GREEN}✓${NC} demo.sh completed"
else
    echo -e "${RED}✗${NC} demo.sh did not finish"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All AnythingLLM checks passed!${NC}"
else
    echo -e "${RED}AnythingLLM checks FAILED!${NC}"
    exit 1
fi
