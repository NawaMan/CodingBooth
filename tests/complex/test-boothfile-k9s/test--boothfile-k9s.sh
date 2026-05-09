#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile k9s Installation
#
# Verifies that `setup k9s` installs the k9s binary.
# k9s is a TUI; we only check it reports a version (no cluster needed).
# Note: `k9s version` prints an ASCII banner first, then a "Version: vX.Y.Z"
# line. k9s wraps labels in ANSI color codes (e.g. \033[36mVersion:\033[0m
# v0.50.18); the closing \033[0m contains the digit 0, which would break a
# [^0-9]* gap. We strip ANSI sequences first, then match "Version: vX.Y.Z".
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile k9s Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- k9s version 2>/dev/null || true)
CLEAN=$(printf '%s' "$ACTUAL" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g')

if echo "$CLEAN" | grep -qiE "version[^0-9]*v?[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "k9s is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "k9s should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
