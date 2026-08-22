#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: cargo--install.sh command emission
#
# Runs the real cargo--install.sh with `sudo` and `cargo` stubbed out, and
# asserts the exact `cargo install` command line it emits. This locks in the
# flag/spec separation: a trailing @version becomes `--version <v>`, and a
# leading-dash flag such as --locked is passed through to every install
# (see docs/REPRODUCIBILITY.md — --locked pins the whole dependency tree).
#
# The script requires root and an installed cargo; we satisfy those with
# a faked EUID + a CARGO_BIN override pointing at a stub, so nothing real is built.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CARGO_SCRIPT="$REPO_ROOT/variants/base/setups/cargo--install.sh"


# Stub directory: a `sudo` that echoes the command it was asked to run, and a
# `cargo` that just exists (so the CARGO_BIN presence check passes).
STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT

cat > "$STUB/sudo" << 'EOF'
#!/bin/bash
echo "STUB_SUDO $*"
EOF

cat > "$STUB/cargo" << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB/sudo" "$STUB/cargo"

# Run cargo--install.sh with the stubs in front of PATH and CARGO_BIN pointed
# at the stub cargo. Captures stdout+stderr (the stub `sudo` echo lands here).
run_cargo_install() {
    PATH="$STUB:$PATH" CARGO_BIN="$STUB/cargo" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$CARGO_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

# Assert the emitted command contains an expected fixed string.
assert_emits() {
    local num="$1" desc="$2" expected="$3"; shift 3
    local out
    out=$(run_cargo_install "$@")
    if echo "$out" | grep -qF -- "$expected"; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "  args:     $*"
        echo "  expected: $expected"
        echo "  actual:   $out"
        ALL_PASSED=false
    fi
}

# Assert the emitted command does NOT contain a string.
assert_absent() {
    local num="$1" desc="$2" needle="$3"; shift 3
    local out
    out=$(run_cargo_install "$@")
    if echo "$out" | grep -qF -- "$needle"; then
        print_test_result "false" "$0" "$num" "$desc"
        echo "  args:       $*"
        echo "  unexpected: $needle"
        echo "  actual:     $out"
        ALL_PASSED=false
    else
        print_test_result "true" "$0" "$num" "$desc"
    fi
}

# 1. Plain crate → bare `cargo install`.
assert_emits 1 "plain crate emits bare install" \
    "cargo install 'ripgrep'" ripgrep

# 2. Pinned crate → translated to --version.
assert_emits 2 "@version translates to --version" \
    "cargo install 'ripgrep' --version '14.1.0'" ripgrep@14.1.0

# 3. --locked + pinned → flag passed through alongside --version.
assert_emits 3 "--locked passes through with a pinned version" \
    "cargo install 'ripgrep' --version '14.1.0' --locked" --locked ripgrep@14.1.0

# 4. --locked without a version → flag passed through to a bare install.
assert_emits 4 "--locked passes through without a version" \
    "cargo install 'ripgrep' --locked" --locked ripgrep

# 5. Default install (no flag) must NOT silently add --locked.
assert_absent 5 "no --locked unless the user asks for it" \
    "--locked" ripgrep@14.1.0

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
