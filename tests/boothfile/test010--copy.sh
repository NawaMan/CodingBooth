#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: copy command

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

copy ./config /opt/config
copy requirements.txt /tmp/requirements.txt
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

if echo "$ACTUAL" | grep -qF "COPY ./config /opt/config"; then
    print_test_result "true" "$0" "010" "copy compiles to COPY (first)"
else
    print_test_result "false" "$0" "010" "copy compiles to COPY (first)"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "COPY requirements.txt /tmp/requirements.txt"; then
    print_test_result "true" "$0" "010" "copy compiles to COPY (second)"
else
    print_test_result "false" "$0" "010" "copy compiles to COPY (second)"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
