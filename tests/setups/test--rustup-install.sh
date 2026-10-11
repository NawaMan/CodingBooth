#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: rustup--install.sh command emission
#
# Runs the real rustup--install.sh with `rustup` stubbed out, and asserts the
# `rustup <kind> add ...` command line it emits: comma lists split into separate
# names, an empty list is a no-op (the rust+targets / rust+components extensions
# default to empty), and an unknown kind fails instead of guessing.
#
# The script requires root and an installed rustup; we satisfy those with a
# faked EUID + a RUSTUP_BIN override pointing at a stub, and a throwaway
# RUSTUP_HOME for the chmod, so nothing real is installed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUSTUP_SCRIPT="$REPO_ROOT/variants/base/setups/rustup--install.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/rustup-home"

cat > "$STUB/rustup" << 'EOF'
#!/bin/bash
echo "STUB_RUSTUP $*"
EOF
chmod +x "$STUB/rustup"

run_rustup_install() {
    RUSTUP_BIN="$STUB/rustup" RUSTUP_HOME="$STUB/rustup-home" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$RUSTUP_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

# Assert the output contains an expected fixed string (and the script exited 0).
assert_emits() {
    local num="$1" desc="$2" expected="$3"; shift 3
    local out rc=0
    out=$(run_rustup_install "$@") || rc=$?
    if [[ $rc -eq 0 ]] && echo "$out" | grep -qF -- "$expected"; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "  args:     $*"
        echo "  expected: $expected (exit 0)"
        echo "  actual:   $out (exit $rc)"
        ALL_PASSED=false
    fi
}

# 1. One target → `rustup target add <target>`.
assert_emits 1 "one target emits rustup target add" \
    "STUB_RUSTUP target add wasm32-unknown-unknown" target wasm32-unknown-unknown

# 2. Comma list → separate names in one call.
assert_emits 2 "comma list splits into separate targets" \
    "STUB_RUSTUP target add wasm32-unknown-unknown aarch64-unknown-linux-gnu" \
    target wasm32-unknown-unknown,aarch64-unknown-linux-gnu

# 3. Components use `rustup component add`.
assert_emits 3 "components emit rustup component add" \
    "STUB_RUSTUP component add llvm-tools miri" component llvm-tools,miri

# 4. Empty list is a no-op that succeeds and never calls rustup.
out=$(run_rustup_install target) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && ! echo "$out" | grep -q STUB_RUSTUP; then
    print_test_result "true" "$0" "4" "empty list is a no-op"
else
    print_test_result "false" "$0" "4" "empty list is a no-op"
    echo "  actual: $out (exit $rc)"
    ALL_PASSED=false
fi

# 5. An unknown kind fails rather than guessing.
out=$(run_rustup_install toolchain stable) && rc=0 || rc=$?
if [[ $rc -ne 0 ]] && ! echo "$out" | grep -q STUB_RUSTUP; then
    print_test_result "true" "$0" "5" "unknown kind fails"
else
    print_test_result "false" "$0" "5" "unknown kind fails"
    echo "  actual: $out (exit $rc)"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
