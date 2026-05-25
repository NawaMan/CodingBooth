#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Smoke test: verify the cache-example booth starts and a simple echo runs.
# The cache mechanism itself is verified by booth start-up (config.toml mounts).
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

echo "=== Testing Cache Example Boot ==="
echo ""

output=$("$BOOTH" --variant base --port "${CB_PORT:-50411}" -- 'echo cache-ok' 2>&1)

echo "$output"
echo ""

failed=0

if grep -q '^cache-ok$' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} Booth started and ran command"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Expected 'cache-ok' in output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Cache example smoke test passed!${NC}"
else
    echo -e "${RED}Cache example smoke test FAILED!${NC}"
    exit 1
fi
