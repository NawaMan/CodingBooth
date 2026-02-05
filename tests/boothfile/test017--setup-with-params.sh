#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: setup command with parameters

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

setup python 3.12
setup jdk 21 temurin
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

if echo "$ACTUAL" | grep -qF "RUN python--setup.sh 3.12"; then
    print_test_result "true" "$0" "017" "setup python 3.12 compiles correctly"
else
    print_test_result "false" "$0" "017" "setup python 3.12 compiles correctly"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "RUN jdk--setup.sh 21 temurin"; then
    print_test_result "true" "$0" "017" "setup jdk 21 temurin compiles correctly"
else
    print_test_result "false" "$0" "017" "setup jdk 21 temurin compiles correctly"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
