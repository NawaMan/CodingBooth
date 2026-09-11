#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile sqluv Installation
#
# Verifies that a Boothfile with `setup sqluv` correctly installs sqluv and
# makes it available in the container.
#
# sqluv has no non-interactive query flags (its TUI needs a real terminal, and
# it takes no --host/--user/--dsn-style arguments at all), so there is no
# headless way to make it actually run a query here. `--help` is checked
# instead of just `--version`, since its output is distinctive enough to prove
# the installed binary really is sqluv and not some unrelated same-named file.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile sqluv Installation ==="

FAILED=0

# Test 1: sqluv is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- sqluv --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "sqluv v[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "sqluv is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "sqluv should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: it really is sqluv, not a same-named stand-in
ACTUAL=$(run_coding_booth --silence-build -- sqluv --help 2>/dev/null)

if echo "$ACTUAL" | grep -q "simple terminal UI for multiple DBMS"; then
    print_test_result "true" "$0" "2" "sqluv prints its own help text"
else
    print_test_result "false" "$0" "2" "sqluv should print its own help text"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
