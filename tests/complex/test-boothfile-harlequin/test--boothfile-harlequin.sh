#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Harlequin Installation
#
# Verifies that a Boothfile with `setup harlequin` correctly installs
# Harlequin AND that it can actually run a query, not just that a binary
# landed on PATH. Harlequin's own TUI needs a real terminal, but the same pip
# package ships `hsql`, a non-interactive "run this SQL and exit" companion
# (like `psql -c`) — used here to run a real query against its bundled
# in-memory DuckDB adapter.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Harlequin Installation ==="

FAILED=0

# Test 1: harlequin is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- harlequin --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qiE "harlequin, version [0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "Harlequin is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Harlequin should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: it actually runs a query, via hsql (its non-interactive companion)
# Everything after `--` is joined into one shell command line (docs/BOOTH_RUN.md),
# so the SQL needs its own quotes to survive as a single argument to -c.
ACTUAL=$(run_coding_booth --silence-build -- "hsql -c 'select 40 + 2 as answer'" 2>/dev/null)

if echo "$ACTUAL" | grep -qE "42"; then
    print_test_result "true" "$0" "2" "Harlequin (hsql) runs a real query"
else
    print_test_result "false" "$0" "2" "Harlequin (hsql) should run a real query"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
