#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Unclosed heredoc produces error

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

run <<END
apt-get update
apt-get install -y curl
EOF

# Capture both stdout and stderr, expect failure
set +e
OUTPUT=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>&1)
EXIT_CODE=$?
set -e

ALL_PASSED=true

# Should produce an error about unclosed heredoc
if echo "$OUTPUT" | grep -qi "unclosed\|unterminated\|heredoc\|END\|delimiter"; then
    print_test_result "true" "$0" "029" "Error about unclosed heredoc"
else
    print_test_result "false" "$0" "029" "Error about unclosed heredoc"
    ALL_PASSED=false
fi

# Should exit with non-zero
if [[ "$EXIT_CODE" -ne 0 ]]; then
    print_test_result "true" "$0" "029" "Non-zero exit code for unclosed heredoc"
else
    print_test_result "false" "$0" "029" "Non-zero exit code for unclosed heredoc"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Output:"
    echo "$OUTPUT"
    echo "Exit code: $EXIT_CODE"
    exit 1
fi
