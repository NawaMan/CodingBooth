#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile floci installation
#
# Verifies that `setup floci` installs the Floci CLI. `floci version` prints
# the CLI version without needing Docker. Starting the emulator and creating
# an S3 bucket is examples/workspaces/floci-example (needs dind).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile floci Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- floci version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if grep -qE "[0-9]+\.[0-9]+\.[0-9]+" <<<"$ACTUAL"; then
    print_test_result "true" "$0" "1" "floci CLI is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "floci CLI should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

HELP_OUTPUT=$(run_coding_booth --silence-build -- 'floci --help' 2>&1) || true

if grep -qE "start" <<<"$HELP_OUTPUT"; then
    print_test_result "true" "$0" "2" "floci help mentions start"
else
    print_test_result "false" "$0" "2" "floci help should mention start"
    echo "  Actual output: $HELP_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
