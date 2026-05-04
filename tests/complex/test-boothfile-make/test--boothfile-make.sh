#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile GNU Make Installation
#
# Verifies that a Boothfile with `setup make --from-apt` correctly installs
# GNU Make and exposes both 'make' and 'gmake' aliases.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile GNU Make Installation ==="

FAILED=0

# Test 1: make is installed
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- make --version)
if echo "$ACTUAL" | grep -qE "GNU Make"; then
    print_test_result "true" "$0" "1" "GNU Make is installed"
else
    print_test_result "false" "$0" "1" "GNU Make should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: gmake alias is exposed (BSD compatibility)
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- gmake --version)
if echo "$ACTUAL" | grep -qE "GNU Make"; then
    print_test_result "true" "$0" "2" "gmake alias is exposed"
else
    print_test_result "false" "$0" "2" "gmake alias should be exposed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: make can run a simple Makefile
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- bash -c 'cd /tmp && printf "hello:\n\t@echo hi-from-make\n" > Makefile && make hello')
if [[ "$ACTUAL" == "hi-from-make" ]]; then
    print_test_result "true" "$0" "3" "make executes a Makefile target"
else
    print_test_result "false" "$0" "3" "make should execute a Makefile target"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
