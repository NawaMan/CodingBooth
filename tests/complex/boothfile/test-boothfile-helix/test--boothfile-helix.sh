#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Helix installation
#
# hx --version only proves the wrapper is on PATH. hx --health reads the
# runtime tree (grammars and queries); without it Helix starts and then
# cannot highlight anything.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Helix Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- hx --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -q "25.07.1"; then
    print_test_result "true" "$0" "1" "Helix 25.07.1 is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Helix 25.07.1 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# --health walks the runtime. "rust" is one of the grammars shipped in the tarball.
ACTUAL=$(run_coding_booth --silence-build -- hx --health 2>&1) || ACTUAL=""
if echo "$ACTUAL" | grep -q "rust"; then
    print_test_result "true" "$0" "2" "hx --health loads the runtime (rust grammar listed)"
else
    print_test_result "false" "$0" "2" "hx --health should list the rust grammar"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
