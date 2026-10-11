#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Rust — usable from `booth exec`, writable, pin-aware
#
# The booth is configured with plain `--select rust`. Checks, all run through
# `booth exec` with no login shell (inBooth-rust.sh):
#   1. cargo runs without /etc/profile.d (RUSTUP_HOME + PATH on the image env),
#      and resolves the rust-toolchain.toml pin baked in by toolchain-file;
#   2. the pin's own target (wasm32) came with it;
#   3. rustfmt, clippy and rust-analyzer are real binaries, not dangling proxies;
#   4. the default toolchain compiles and runs a program;
#   5. the booth user can `rustup target add`, and build for that target.
# cargo new + rustup target add reach the network.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Rust ==="

FAILED=0
ACTUAL=$(run_coding_booth exec --run --silence-build -- bash inBooth-rust.sh 2>/dev/null) || ACTUAL=""

# check <num> <label> <pattern> <description>: the line "<label>: ..." matches the pattern.
check() {
    local num="$1" label="$2" pattern="$3" desc="$4" line
    line=$(echo "$ACTUAL" | grep "^${label}: " | head -1)
    if echo "$line" | grep -qE -- "^${label}: ${pattern}"; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "  Actual line: ${line:-<none>}"
        FAILED=$((FAILED + 1))
    fi
}

check 1 pin-cargo  'cargo 1\.90\.0 '  "booth exec runs cargo, on the rust-toolchain.toml pin"
check 2 pin-wasm   '1$'               "the pin's wasm32 target was baked in with it"
check 3 fmt        'ok$'              "cargo fmt works without a login shell"
check 4 clippy     'ok$'              "cargo clippy works without a login shell"
check 5 analyzer   'ok$'              "rust-analyzer is installed, not a dangling proxy"
check 6 run        'Hello, world!$'   "the default toolchain compiles and runs a program"
check 7 add-target '1$'               "the booth user can rustup target add"
check 8 wasm-build 'ok$'              "and build for the added target"

if [[ $FAILED -ne 0 ]]; then
    echo "  Full output:"; echo "$ACTUAL" | sed 's/^/    /'
fi
exit $FAILED
