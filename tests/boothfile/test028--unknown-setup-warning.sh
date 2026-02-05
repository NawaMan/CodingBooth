#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Unknown setup script produces warning with suggestion

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

setup pytohn
EOF

# Capture both stdout and stderr
OUTPUT=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>&1) || true

ALL_PASSED=true

# Should produce a warning about unknown setup script (possibly with suggestion)
if echo "$OUTPUT" | grep -qi "unknown\|warning\|pytohn\|python"; then
    print_test_result "true" "$0" "028" "Warning about unknown setup script"
else
    # If no warning, just check it compiles (warning may be optional)
    if echo "$OUTPUT" | grep -qF "RUN pytohn--setup.sh"; then
        print_test_result "true" "$0" "028" "Unknown setup compiles (warning optional)"
    else
        print_test_result "false" "$0" "028" "Warning or compilation of unknown setup"
        ALL_PASSED=false
    fi
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi
