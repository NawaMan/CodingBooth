#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for Appwrite example.
# Verifies the CLI is installed and the self-hosted API answers /v1/health/version.
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

echo "=== Testing Appwrite CLI + server health ==="
echo ""

# First boot pulls the Appwrite Compose stack inside DinD — several minutes.
output=$("$BOOTH" --variant base --port "${CB_PORT:-50280}" -- 'just run' 2>&1) || true

echo "$output"
echo ""

failed=0

if grep -qE '^[0-9]+\.[0-9]+' <<< "$output" || grep -qi 'appwrite' <<< "$output"; then
    echo -e "${GREEN}✓${NC} Appwrite CLI produced a version"
else
    echo -e "${RED}✗${NC} Appwrite CLI version missing"
    failed=1
fi

if grep -qi 'version' <<< "$output" && grep -qiE '1\.[0-9]|2\.[0-9]' <<< "$output"; then
    echo -e "${GREEN}✓${NC} Appwrite API health returned a version"
else
    echo -e "${RED}✗${NC} Appwrite API health missing"
    failed=1
fi

if grep -q 'CLI and server are both working' <<< "$output"; then
    echo -e "${GREEN}✓${NC} demo.sh completed"
else
    echo -e "${RED}✗${NC} demo.sh did not finish"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All Appwrite checks passed!${NC}"
else
    echo -e "${RED}Appwrite checks FAILED!${NC}"
    exit 1
fi
