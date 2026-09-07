#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Mojo Installation
#
# Verifies that `setup mojo` (with python already in the Boothfile) installs
# the Mojo compiler and that it can compile and run a program — not only that
# `mojo --version` prints a string.
# mojo--setup.sh is loaded from .booth/setups/ so the test works before the
# script ships in the Docker Hub base image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Mojo Installation ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# Test 1: mojo is on PATH
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- mojo --version) || ACTUAL=""
if echo "$ACTUAL" | grep -qiE "mojo"; then
    print_test_result "true" "$0" "1" "Mojo is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Mojo should be installed"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

# Test 2: compile and run a program (the first-five-minutes check)
HELLO_CMD='printf "def main():\n    print(\"Hello from Mojo\")\n" > /tmp/hello.mojo && mojo /tmp/hello.mojo'
ACTUAL=$(capture_codingbooth "cat" --silence-build -- "$HELLO_CMD") || ACTUAL=""
if echo "$ACTUAL" | grep -q "Hello from Mojo"; then
    print_test_result "true" "$0" "2" "Mojo compiles and runs a program"
else
    print_test_result "false" "$0" "2" "Mojo should compile and run a program"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
