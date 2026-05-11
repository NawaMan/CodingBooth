#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Smoke test: verify Ruby is installed in the Rails example booth.
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

echo "=== Testing Ruby Availability (Rails example) ==="
echo ""

output=$("$BOOTH" --variant base --port "${CB_PORT:-50541}" -- 'ruby --version' 2>&1)

echo "$output"
echo ""

failed=0

if echo "$output" | grep -qE '^ruby 3\.3'; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} Found Ruby 3.3"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Expected Ruby 3.3 but got: $output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Ruby smoke test passed!${NC}"
else
    echo -e "${RED}Ruby smoke test FAILED!${NC}"
    exit 1
fi
