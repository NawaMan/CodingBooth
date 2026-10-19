#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Smoke test: verify the omp CLI is on PATH inside the booth.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

echo "=== Testing Oh My Pi Availability ==="
echo ""

output=$("$BOOTH" --variant base --port "${CB_PORT:-50428}" -- 'command -v omp && omp --version' 2>&1) || true

echo "$output"
echo ""

failed=0

if grep -qE 'omp/[0-9]' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} omp CLI is available"
else
    echo -e "${RED}\xe2\x9c\x97${NC} omp CLI not found"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Oh My Pi smoke test passed!${NC}"
else
    echo -e "${RED}Oh My Pi smoke test FAILED!${NC}"
    exit 1
fi
