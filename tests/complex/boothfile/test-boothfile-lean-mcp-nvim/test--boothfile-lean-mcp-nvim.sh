#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Lean MCP server + Neovim (lean+mcp, lean+nvim) -- EXPERIMENTAL
#
# Verifies that lean+mcp and lean+nvim work on a real project: lean-lsp-mcp answers an MCP
# client over stdio (the goal at a sorry, the file's diagnostics), and a headless Neovim
# opens a .lean file and gets the Lean language server attached, with diagnostics.
#
# The assertions live in checks/test*.sh and run inside the booth; each prints
# ✓/✗ lines and exits non-zero on a failure. Needs network (Lean toolchain).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Lean MCP server + Neovim (lean+mcp, lean+nvim) ==="

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
