#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Syntax directive is required and transforms to docker/dockerfile:1.7

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

run echo "hello"
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# Should have docker syntax, not boothfile syntax
if echo "$ACTUAL" | grep -qF "# syntax=docker/dockerfile:1.7"; then
    print_test_result "true" "$0" "002" "Output has docker/dockerfile:1.7 syntax"
else
    print_test_result "false" "$0" "002" "Output has docker/dockerfile:1.7 syntax"
    ALL_PASSED=false
fi

# Should NOT have boothfile syntax in output
if echo "$ACTUAL" | grep -qF "codingbooth/boothfile"; then
    print_test_result "false" "$0" "002" "Output should not contain boothfile syntax"
    ALL_PASSED=false
else
    print_test_result "true" "$0" "002" "Output does not contain boothfile syntax"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
