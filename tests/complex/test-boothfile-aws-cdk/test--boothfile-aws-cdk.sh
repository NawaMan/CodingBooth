#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile AWS CDK Installation
#
# Verifies that a Boothfile with `setup nodejs` and `setup aws-cdk` correctly
# installs AWS CDK CLI and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile AWS CDK Installation ==="

FAILED=0

# Match with a here-string, never `echo "$X" | grep -q`. `grep -q` exits at the
# first match, and bash's `echo` builtin writes its argument in buffer-sized
# chunks — so on anything past a few KB the next write lands on a closed pipe,
# echo dies of SIGPIPE (141), and `set -o pipefail` reports the whole pipeline as
# a failure even though the text matched. `cdk --help` is ~10KB, right at the size
# where that race is a coin flip: measured 16 failures in 40 runs. A here-string
# has no writer process to kill.

# Test 1: CDK is installed and shows a version number
ACTUAL=$(run_coding_booth --silence-build -- cdk --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if grep -qE "[0-9]+\.[0-9]+\.[0-9]+" <<<"$ACTUAL"; then
    print_test_result "true" "$0" "1" "AWS CDK is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "AWS CDK should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: CDK help includes synth or deploy commands
HELP_OUTPUT=$(run_coding_booth --silence-build -- cdk --help 2>&1) || true

if grep -qE "synth|deploy" <<<"$HELP_OUTPUT"; then
    print_test_result "true" "$0" "2" "AWS CDK help includes synth/deploy commands"
else
    print_test_result "false" "$0" "2" "AWS CDK help should include synth/deploy commands"
    echo "  Actual output: $HELP_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
