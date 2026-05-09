#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile kubectx Installation
#
# Verifies that `setup kubectx` installs both kubectx and kubens
# (they ship as a pair from the same upstream repo).
#
# Note: kubectx/kubens are bash scripts that preflight `hash kubectl` before
# parsing args, so `kubectx --help` errors out without kubectl. We just check
# the binaries exist on disk; that proves the setup ran.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile kubectx Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- ls /usr/local/bin/kubectx /usr/local/bin/kubens 2>/dev/null || true)

if echo "$ACTUAL" | grep -q "/kubectx$"; then
    print_test_result "true" "$0" "1" "kubectx is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "kubectx should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -q "/kubens$"; then
    print_test_result "true" "$0" "2" "kubens is installed alongside kubectx"
else
    print_test_result "false" "$0" "2" "kubens should be installed alongside kubectx"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
