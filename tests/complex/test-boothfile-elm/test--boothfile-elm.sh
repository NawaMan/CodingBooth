#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Elm Installation
#
# Verifies that a Boothfile with `setup elm --version 0.19.1` installs Elm
# via npm (depends on prior `setup nodejs`).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

# On arm64, Elm 0.19.1's npm wrapper resolves to a non-existent linux binary;
# elm--setup.sh has an arm64 fallback that the Hub image doesn't carry yet.
use_local_base_image || exit 0

echo "=== Test: Boothfile Elm Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- elm --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE '^0\.19'; then
    print_test_result "true" "$0" "1" "Elm is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Elm should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
