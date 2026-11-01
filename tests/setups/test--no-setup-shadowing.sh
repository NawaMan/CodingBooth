#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: build/check-setup-shadowing.sh — no .booth/setups/ copy of a built-in
#
# A test fixture or example whose .booth/setups/ holds a file named like a
# built-in setup runs that copy instead of the one the image ships. This fails
# the suite while any such copy exists in the repo, and proves the guard on a
# fixture tree:
#
#   1. this repo has no shadowing copy
#   2. a copy of a built-in setup is caught and named
#   3. a copy of a built-in lib (libs/skip-setup.sh) is caught too
#   4. a script the project adds under its own name passes
#   5. a copy inside a nested worktree/ (another checkout) is not counted
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/build/check-setup-shadowing.sh"

ALL_PASSED=true
TEST_NUM=0
report() {  # report <ok> <desc> [detail-lines...]
    local ok="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        for line in "$@"; do echo "      $line"; done
        ALL_PASSED=false
    fi
}

out="$(bash "$GUARD" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
    report true "no .booth/setups/ file in this repo shadows a built-in setup"
else
    report false "no .booth/setups/ file in this repo shadows a built-in setup" "$out"
fi

# A fixture tree, outside git, so the guard falls back to walking every file.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/variants/base/setups/libs"
echo '# built-in' > "$TMP/variants/base/setups/helm--setup.sh"
echo '# built-in' > "$TMP/variants/base/setups/libs/skip-setup.sh"

fixture() {  # fixture <relative path>...: a fresh tree holding these .booth files
    rm -rf "$TMP/tests" "$TMP/examples" "$TMP/worktree"
    local f
    for f in "$@"; do mkdir -p "$TMP/$(dirname "$f")"; echo '# copy' > "$TMP/$f"; done
}

fixture tests/complex/test-helm/.booth/setups/helm--setup.sh
out="$(bash "$GUARD" "$TMP" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -qF "tests/complex/test-helm/.booth/setups/helm--setup.sh  (shadows variants/base/setups/helm--setup.sh)"; then
    report true "a copy of a built-in setup fails the check and is named"
else
    report false "a copy of a built-in setup fails the check and is named" "rc=$rc" "$out"
fi

fixture examples/workspaces/demo/.booth/setups/libs/skip-setup.sh
out="$(bash "$GUARD" "$TMP" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -qF "demo/.booth/setups/libs/skip-setup.sh"; then
    report true "a copy of a built-in lib fails the check"
else
    report false "a copy of a built-in lib fails the check" "rc=$rc" "$out"
fi

fixture examples/workspaces/lamp/.booth/setups/lamp-init--setup.sh
out="$(bash "$GUARD" "$TMP" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
    report true "a script the project adds under its own name passes"
else
    report false "a script the project adds under its own name passes" "rc=$rc" "$out"
fi

fixture worktree/other/tests/complex/test-helm/.booth/setups/helm--setup.sh
out="$(bash "$GUARD" "$TMP" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
    report true "a copy inside a nested worktree/ checkout is not counted"
else
    report false "a copy inside a nested worktree/ checkout is not counted" "rc=$rc" "$out"
fi

[ "$ALL_PASSED" = true ]
