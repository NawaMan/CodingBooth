#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Full-line comments are preserved in output (for readability)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

# This is a full-line comment
# Another comment here
run echo "test"
# Comment after command
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# Comments should be preserved (except syntax directive which transforms)
if echo "$ACTUAL" | grep -qF "This is a full-line comment"; then
    print_test_result "true" "$0" "003" "Full-line comments are preserved"
else
    print_test_result "false" "$0" "003" "Full-line comments are preserved"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "Another comment here"; then
    print_test_result "true" "$0" "003" "All comments are preserved"
else
    print_test_result "false" "$0" "003" "All comments are preserved"
    ALL_PASSED=false
fi

# The run command should still be present
if echo "$ACTUAL" | grep -qF 'RUN echo "test"'; then
    print_test_result "true" "$0" "003" "Commands are preserved"
else
    print_test_result "false" "$0" "003" "Commands are preserved"
    ALL_PASSED=false
fi

# The syntax directive comment should NOT be preserved (it's transformed)
if echo "$ACTUAL" | grep -qF "# syntax=codingbooth/boothfile"; then
    print_test_result "false" "$0" "003" "Syntax directive should be transformed"
    ALL_PASSED=false
else
    print_test_result "true" "$0" "003" "Syntax directive is transformed"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
