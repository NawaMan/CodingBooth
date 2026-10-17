#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for Appwrite example.
# Verifies the CLI is installed, the self-hosted API answers /v1/health/version,
# and `just app` prepares the starter-for-svelte project so a ping from the
# starter's browser origin is accepted.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

echo "=== Testing Appwrite CLI + server health ==="
echo ""

# First boot pulls the Appwrite Compose stack inside DinD — several minutes.
# --dind-allowed: this example's dind = true would otherwise stop for a [y/N]
# consent prompt on /dev/tty (see docs/BOOTH_SECURITY.md) — silent in a script.
output=$("$BOOTH" --dind-allowed --variant base --port "${CB_PORT:-50280}" -- 'just run && just app' 2>&1) || true

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

if grep -q 'ping: Pong!' <<< "$output" && grep -q 'Appwrite project ready for starter-for-svelte' <<< "$output"; then
    echo -e "${GREEN}✓${NC} just app: starter project answers a ping from the starter's origin"
else
    echo -e "${RED}✗${NC} just app did not prepare the starter project"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All Appwrite checks passed!${NC}"
else
    echo -e "${RED}Appwrite checks FAILED!${NC}"
    exit 1
fi
