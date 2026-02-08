#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test that init-generated Go Boothfile compiles to a valid Dockerfile

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/init-go-test"

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

EXPECT_CONTAINS=(
    "# syntax=docker/dockerfile:1.7"
    "ARG GO_VERSION=1.24"
    "RUN go--setup.sh \${GO_VERSION}"
)

ALL_PASSED=true

for expected in "${EXPECT_CONTAINS[@]}"; do
    if echo "$ACTUAL" | grep -qF "$expected"; then
        print_test_result "true" "$0" "init-go" "Output contains: $expected"
    else
        print_test_result "false" "$0" "init-go" "Output should contain: $expected"
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

print_test_result "true" "$0" "init-go" "Init-generated Go Boothfile compiles"
