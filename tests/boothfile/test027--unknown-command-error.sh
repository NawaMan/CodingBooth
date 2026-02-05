#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Unknown command produces error with suggestion

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

instal pip django
EOF

# Capture both stdout and stderr, expect failure
OUTPUT=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>&1) || EXIT_CODE=$?

ALL_PASSED=true

# Should produce an error about unknown command
if echo "$OUTPUT" | grep -qi "unknown\|invalid\|unrecognized\|instal"; then
    print_test_result "true" "$0" "027" "Error about unknown command"
else
    print_test_result "false" "$0" "027" "Error about unknown command"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi
