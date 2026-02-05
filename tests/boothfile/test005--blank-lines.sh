#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Blank lines are ignored

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1


env VAR1=one


env VAR2=two

EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# Both env commands should be present
if echo "$ACTUAL" | grep -qF "ENV VAR1=one"; then
    print_test_result "true" "$0" "005" "ENV VAR1 is present"
else
    print_test_result "false" "$0" "005" "ENV VAR1 is present"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "ENV VAR2=two"; then
    print_test_result "true" "$0" "005" "ENV VAR2 is present"
else
    print_test_result "false" "$0" "005" "ENV VAR2 is present"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
