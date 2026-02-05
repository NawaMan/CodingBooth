#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Inline comments are stripped from output

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

env MY_VAR=value # This is an inline comment
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# The env command should be present
if echo "$ACTUAL" | grep -qF "ENV MY_VAR=value"; then
    print_test_result "true" "$0" "004" "ENV command is preserved"
else
    print_test_result "false" "$0" "004" "ENV command is preserved"
    ALL_PASSED=false
fi

# Inline comment should be stripped
if echo "$ACTUAL" | grep -qF "inline comment"; then
    print_test_result "false" "$0" "004" "Inline comments should be stripped"
    ALL_PASSED=false
else
    print_test_result "true" "$0" "004" "Inline comments are stripped"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
