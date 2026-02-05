#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test --boothfile flag to explicitly specify a Boothfile

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/boothfile-test"
BOOTHFILE_PATH="$TEST_DIR/.booth/Boothfile"

# Run with explicit --boothfile
ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" --boothfile "$BOOTHFILE_PATH" 2>/dev/null)

# Should produce the same output as auto-detected Boothfile
EXPECT_CONTAINS=(
    "RUN python--setup.sh 3.12"
    "RUN pip--install.sh django"
    "ENV APP_ENV=production"
)

ALL_PASSED=true

for expected in "${EXPECT_CONTAINS[@]}"; do
    if echo "$ACTUAL" | grep -qF "$expected"; then
        print_test_result "true" "$0" "boothfile-flag" "Output contains: $expected"
    else
        print_test_result "false" "$0" "boothfile-flag" "Output contains: $expected"
        ALL_PASSED=false
    fi
done

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "-------------------------------------------------------------------------------"
    echo "Actual output:"
    echo "$ACTUAL"
    echo "-------------------------------------------------------------------------------"
    exit 1
fi

print_test_result "true" "$0" "boothfile-flag" "--boothfile flag works correctly"
