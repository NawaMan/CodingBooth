#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test that Java is properly installed and returns expected version output
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Testing Java Version ==="
echo ""

# Capture java -version output (note: java -version outputs to stderr)
output=$("$SCRIPT_DIR/../../../coding-booth" --variant base --silence-build -- 'java -version' 2>&1)

echo "$output"
echo ""

# Validate output contains expected patterns
failed=0

if echo "$output" | grep -qi "openjdk version"; then
    echo -e "${GREEN}✓${NC} Found 'openjdk version'"
else
    echo -e "${RED}✗${NC} Missing 'openjdk version'"
    failed=1
fi

if echo "$output" | grep -qi "OpenJDK Runtime Environment"; then
    echo -e "${GREEN}✓${NC} Found 'OpenJDK Runtime Environment'"
else
    echo -e "${RED}✗${NC} Missing 'OpenJDK Runtime Environment'"
    failed=1
fi

if echo "$output" | grep -qi "OpenJDK.*Server VM"; then
    echo -e "${GREEN}✓${NC} Found 'OpenJDK Server VM'"
else
    echo -e "${RED}✗${NC} Missing 'OpenJDK Server VM'"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All Java version checks passed!${NC}"
else
    echo -e "${RED}Java version checks FAILED!${NC}"
    exit 1
fi
