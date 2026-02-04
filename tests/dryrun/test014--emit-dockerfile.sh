#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test --emit-dockerfile flag with a Boothfile

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/boothfile-test"

# Run with --emit-dockerfile
ACTUAL=$(run_coding_booth --code "$TEST_DIR" --emit-dockerfile 2>/dev/null)

# Expected output should contain the Dockerfile prologue and compiled commands
EXPECT_CONTAINS=(
    "# syntax=docker/dockerfile:1"
    "ARG BOOTH_VARIANT_TAG=base"
    "ARG BOOTH_VERSION_TAG=latest"
    "FROM nawaman/codingbooth:"
    "SHELL"
    "USER root"
    "WORKDIR /opt/codingbooth/setups"
    "RUN python--setup.sh 3.12"
    "RUN pip--install.sh django"
    "ENV APP_ENV=production"
)

ALL_PASSED=true

for expected in "${EXPECT_CONTAINS[@]}"; do
    if echo "$ACTUAL" | grep -qF "$expected"; then
        print_test_result "true" "$0" "emit-dockerfile" "Output contains: $expected"
    else
        print_test_result "false" "$0" "emit-dockerfile" "Output contains: $expected"
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

# Test that it exits cleanly (exit code 0)
print_test_result "true" "$0" "emit-dockerfile" "--emit-dockerfile exits successfully"
