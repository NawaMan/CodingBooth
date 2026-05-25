#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Smoke test: verify Node.js is installed in the Angular example booth.
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

echo "=== Testing Node.js Availability (Angular example) ==="
echo ""

output=$("$BOOTH" --variant base --port "${CB_PORT:-50401}" -- 'node --version' 2>&1)

echo "$output"
echo ""

failed=0

if grep -qE '^v22\.' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} Found Node.js v22"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Expected Node.js v22 but got: $output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Node.js smoke test passed!${NC}"
else
    echo -e "${RED}Node.js smoke test FAILED!${NC}"
    exit 1
fi
