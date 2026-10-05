#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Xonsh installation
#
# xonsh --version proves a binary. xonsh -c runs the shell language: Python
# expressions and the shell primitive `echo @(...)` in one process.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Xonsh Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- xonsh --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -q "0.24.2"; then
    print_test_result "true" "$0" "1" "Xonsh 0.24.2 is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Xonsh 0.24.2 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# One shot, no TTY. 20 + 22 is Python; echo @(...) is the xonsh shell primitive.
# One argv after --: codingbooth joins args and re-parses them with bash -lc,
# so a separate `bash -c` would keep only the first word of the script.
ACTUAL=$(run_coding_booth --silence-build -- 'xonsh -c "print(20 + 22); echo @(6 * 7)"' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -q "42" && echo "$ACTUAL" | grep -q "42"; then
    # Both lines are 42. Require two occurrences so a single stray 42 cannot pass.
    count=$(echo "$ACTUAL" | grep -c "42" || true)
    if [[ "$count" -ge 2 ]]; then
        print_test_result "true" "$0" "2" "xonsh -c evaluates Python and a shell primitive"
    else
        print_test_result "false" "$0" "2" "xonsh -c should print 42 twice"
        echo "  Actual output: $ACTUAL"
        FAILED=$((FAILED + 1))
    fi
else
    print_test_result "false" "$0" "2" "xonsh -c should print 42 from Python and from echo @()"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
