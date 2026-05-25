#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test that jbang can execute inline Java source code
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=== Testing jbang Source Execution ==="
echo ""

# Run jbang with inline Java source
output=$("../../../codingbooth" --variant base --port "${CB_PORT:-50012}" -- '
cat > /tmp/Test.java << "EOFJAVA"
import java.nio.file.*;
import java.util.Arrays;

class Test {
    public static void main(String[] args) {
        System.out.println("🚀 JDK: " + System.getProperty("java.version"));
        System.out.println("📁 CWD: " + Paths.get("").toAbsolutePath());
        System.out.println("🔧 Args: " + Arrays.toString(args));
        for (int i = 0; i < 3; i++) {
            System.out.println("line " + i);
        }
    }
}
EOFJAVA
jbang --quiet /tmp/Test.java one "two 2"
' 2>&1)

echo "$output"
echo ""

# Validate output contains expected patterns
failed=0

# Check for JDK version line
if grep -q "🚀 JDK:" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Found JDK version output"
else
    echo -e "${RED}✗${NC} Missing JDK version output"
    failed=1
fi

# Check for CWD line
if grep -q "📁 CWD:" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Found CWD output"
else
    echo -e "${RED}✗${NC} Missing CWD output"
    failed=1
fi

# Check for Args line with expected arguments
if grep -q "🔧 Args: \[one, two 2\]" <<< "$output"; then
    echo -e "${GREEN}✓${NC} Found correct arguments"
else
    echo -e "${RED}✗${NC} Missing or incorrect arguments"
    failed=1
fi

# Check for numbered lines
for i in 0 1 2; do
    if grep -q "line $i" <<< "$output"; then
        echo -e "${GREEN}✓${NC} Found 'line $i'"
    else
        echo -e "${RED}✗${NC} Missing 'line $i'"
        failed=1
    fi
done

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All jbang source execution checks passed!${NC}"
else
    echo -e "${RED}jbang source execution checks FAILED!${NC}"
    exit 1
fi
