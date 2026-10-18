#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# The stack actually serves: MySQL starts on boot and the page shows the row PHP read from it.
# test001 only checks `php --version`, which passed while mysqld never started.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

echo "=== Testing LAMP page (Apache + PHP + MySQL) ==="
echo ""

output=$("$BOOTH" --variant base --port "${CB_PORT:-50462}" -- './demo.sh page' 2>&1) || true

echo "$output"
echo ""

if grep -qF 'Hi from MySQL!' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} Found: Hi from MySQL!"
    echo -e "${GREEN}LAMP page test passed!${NC}"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Missing: Hi from MySQL!"
    echo -e "${RED}LAMP page test FAILED!${NC}"
    exit 1
fi
