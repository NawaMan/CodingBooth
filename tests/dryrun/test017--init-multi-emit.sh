#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test that init-generated multi-template Boothfile compiles correctly

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/init-multi-test"

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

EXPECT_CONTAINS=(
    "# syntax=docker/dockerfile:1.7"
    "ARG GO_VERSION=1.22"
    "ARG PYTHON_VERSION=3.12"
    "RUN go--setup.sh \${GO_VERSION}"
    "RUN python--setup.sh \${PYTHON_VERSION}"
)

ALL_PASSED=true

for expected in "${EXPECT_CONTAINS[@]}"; do
    if echo "$ACTUAL" | grep -qF "$expected"; then
        print_test_result "true" "$0" "init-multi" "Output contains: $expected"
    else
        print_test_result "false" "$0" "init-multi" "Output should contain: $expected"
        ALL_PASSED=false
    fi
done

# Verify ordering: Go setup before Python setup (alphabetical tiebreak)
GO_LINE=$(echo "$ACTUAL" | grep -n "go--setup.sh" | head -1 | cut -d: -f1)
PY_LINE=$(echo "$ACTUAL" | grep -n "python--setup.sh" | head -1 | cut -d: -f1)

if [[ -n "$GO_LINE" && -n "$PY_LINE" && "$GO_LINE" -lt "$PY_LINE" ]]; then
    print_test_result "true" "$0" "init-multi" "Go setup appears before Python setup"
else
    print_test_result "false" "$0" "init-multi" "Go setup should appear before Python setup"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "-------------------------------------------------------------------------------"
    echo "Actual output:"
    echo "$ACTUAL"
    echo "-------------------------------------------------------------------------------"
    exit 1
fi

print_test_result "true" "$0" "init-multi" "Init-generated multi-template Boothfile compiles"
