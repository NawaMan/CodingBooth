#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Lean blueprint (lean+blueprint) -- EXPERIMENTAL
#
# Verifies that lean+blueprint builds a real blueprint: the Lean project (one intended
# sorry), the web version with its dependency graph, the PDF, checkdecls (and that it rejects
# an unknown name), and the leanblueprint CLI itself on a git copy.
#
# The assertions live in checks/test*.sh and run inside the booth; each prints
# ✓/✗ lines and exits non-zero on a failure. Needs network (Lean toolchain).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Lean blueprint (lean+blueprint) ==="

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
