#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Minimal Boothfile (only syntax line) generates prologue only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

EXPECT_CONTAINS=(
    "# syntax=docker/dockerfile:1.7"
    "ARG BOOTH_VARIANT_TAG=base"
    "ARG BOOTH_VERSION_TAG=latest"
    "FROM nawaman/codingbooth:"
)

ALL_PASSED=true

for expected in "${EXPECT_CONTAINS[@]}"; do
    if echo "$ACTUAL" | grep -qF "$expected"; then
        print_test_result "true" "$0" "001" "Output contains: $expected"
    else
        print_test_result "false" "$0" "001" "Output contains: $expected"
        ALL_PASSED=false
    fi
done

# Ensure no RUN/COPY/ENV commands beyond prologue
if echo "$ACTUAL" | grep -qE "^RUN |^COPY |^ENV "; then
    print_test_result "false" "$0" "001" "Minimal boothfile should not have RUN/COPY/ENV commands"
    ALL_PASSED=false
else
    print_test_result "true" "$0" "001" "Minimal boothfile has no extra commands"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
