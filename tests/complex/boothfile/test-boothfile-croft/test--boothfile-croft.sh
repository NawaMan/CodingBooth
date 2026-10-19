#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Croft installation
#
# croft --version only proves a binary landed on PATH. `croft plot` charts
# numbers from stdin, which is a command a user runs without opening the TUI.
#
# croft--setup.sh is copied under .booth/setups/ until the base image ships it.
# Delete that copy before landing, then rebuild base and re-run this test.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Croft Installation ==="

FAILED=0

ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'croft --version')
if [[ "$ACTUAL" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    print_test_result "true" "$0" "1" "croft --version reports a release"
else
    print_test_result "false" "$0" "1" "croft --version should report a release"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Axis labels are the last sample (4) and the first (1). The body is a braille chart.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'printf "1\n2\n3\n4\n" | croft plot')
first="${ACTUAL%%$'\n'*}"
if [[ "$first" == 4\ * && "$ACTUAL" == *$'\n'1\ * ]]; then
    print_test_result "true" "$0" "2" "croft plot charts stdin"
else
    print_test_result "false" "$0" "2" "croft plot should chart stdin"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
