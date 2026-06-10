#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: install cargo with a pass-through flag (--locked)
#
# A leading-dash token on an `install cargo` line must survive compilation
# verbatim (not be stripped, reordered, or mistaken for a directive), so that
# cargo--install.sh can forward it to `cargo install`. --locked is the flag
# that makes cargo honor the crate's published Cargo.lock for a fixed
# dependency tree (see docs/REPRODUCIBILITY.md).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

install cargo --locked ripgrep@14.1.0 fd-find
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

if echo "$ACTUAL" | grep -qF "RUN cargo--install.sh --locked ripgrep@14.1.0 fd-find"; then
    print_test_result "true" "$0" "031" "install cargo --locked passes the flag through to cargo--install.sh"
else
    print_test_result "false" "$0" "031" "install cargo --locked passes the flag through to cargo--install.sh"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
