#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile LeanInteract (lean+interact) -- EXPERIMENTAL
#
# Verifies that lean+interact gives a notebook booth in which Python drives Lean: the REPL
# is prebuilt into the image, a proof search script runs, and the notebook runs top to bottom.
#
# The assertions live in checks/test*.sh and run inside the booth; each prints
# ✓/✗ lines and exits non-zero on a failure. Needs network (Lean toolchain).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile LeanInteract (lean+interact) ==="

ACTUAL=$(run_coding_booth --silence-build -- ./checks/run-all.sh 2>&1) || true
echo "$ACTUAL" | grep -E '^(===|  [✓✗]|>>>)' || true

FAILED=0
N=0
for check in checks/test[0-9][0-9][0-9]-*.sh; do
    N=$((N + 1))
    name="$(basename "$check")"
    if echo "$ACTUAL" | grep -qx ">>> PASSED: $name"; then
        print_test_result "true" "$0" "$N" "$name"
    else
        print_test_result "false" "$0" "$N" "$name"
        FAILED=$((FAILED + 1))
    fi
done

exit $FAILED
