#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Gleam Installation
#
# Verifies that `setup erlang` + `setup gleam --version 1.18.1` give a booth in
# which gleam can create, run and test a project — not just print a version.
# gleam new/run/test fetch gleam_stdlib and gleeunit from Hex, so this needs network.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Gleam Installation ==="

FAILED=0

# Test 1: the pinned version is the one installed
ACTUAL=$(run_coding_booth --silence-build -- gleam --version 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "gleam 1.18.1" ]]; then
    print_test_result "true" "$0" "1" "Gleam 1.18.1 is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Gleam 1.18.1 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2-3: a fresh project compiles to Erlang, runs on the BEAM, and its tests pass.
# No quotes in the script: it round-trips through codingbooth's COMMAND mode
# (argv -> joined string -> re-parsed by bash -c).
RUN_SCRIPT='
cd /tmp && rm -rf demo && gleam new demo >/dev/null && cd demo
gleam run 2>/dev/null | tail -1
gleam test 2>&1 | tail -1
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$RUN_SCRIPT" 2>/dev/null) || ACTUAL=""

if echo "$ACTUAL" | grep -q "Hello from demo!"; then
    print_test_result "true" "$0" "2" "gleam new + gleam run compiles and runs a program"
else
    print_test_result "false" "$0" "2" "gleam run should print Hello from demo!"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -q "1 passed, no failures"; then
    print_test_result "true" "$0" "3" "gleam test runs the project's tests"
else
    print_test_result "false" "$0" "3" "gleam test should pass the generated test"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
