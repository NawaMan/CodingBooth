#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for mvn-deps example.
# Verifies that Maven dependencies are pre-downloaded and the project compiles and runs.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
if [ -x "$REPO_ROOT/codingbooth" ]; then
    BOOTH="$REPO_ROOT/codingbooth"
else
    BOOTH="$REPO_ROOT/booth"
fi

echo "=== Test 001: Maven Dependencies from pom.xml ==="
echo ""

failed=0

# Test that maven can compile and run the project
echo "Testing maven compile and exec..."
output=$("$BOOTH" --variant base --port "${CB_PORT:-50331}" -- 'mvn compile -B -q exec:java -Dexec.mainClass=com.example.App' 2>&1) || true

if grep -q "Hello from maven" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Maven project compiled and ran successfully"
else
    echo -e "${RED}✗${NC} Maven project failed to compile or run"
    echo "$output"
    failed=1
fi

# Check that there are no build errors
if grep -q "BUILD FAILURE" <<< "$output"; then
    echo -e "${RED}✗${NC} Maven build failed"
    failed=1
else
    echo -e "${GREEN}✓${NC} No build failures detected"
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All Maven dependency tests passed!${NC}"
else
    echo -e "${RED}Some Maven dependency tests FAILED!${NC}"
    exit 1
fi
