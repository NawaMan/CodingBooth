#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Smoke test: verify Python is installed in the Flask example booth.
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

echo "=== Testing Python Availability (Flask example) ==="
echo ""

output=$("$BOOTH" --variant base --port "${CB_PORT:-50451}" -- 'python --version' 2>&1) || true

echo "$output"
echo ""

failed=0

if grep -qE 'Python 3\.13' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} Found Python 3.13"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Expected Python 3.13 but got: $output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Python smoke test passed!${NC}"
else
    echo -e "${RED}Python smoke test FAILED!${NC}"
    exit 1
fi
