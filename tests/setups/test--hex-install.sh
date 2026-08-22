#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: hex--install.sh command emission
#
# Runs the real hex--install.sh with `mix` stubbed, and asserts the
# `mix archive.install` command line it emits. This locks in the
# name@version → positional-version translation (Mix takes the version as a
# positional argument, not a flag) and comma-list splitting.
#
# The script requires root and an installed mix; we satisfy those with
# a faked EUID + an ELIXIR_HOME override pointing at a stub, so nothing real runs.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HEX_SCRIPT="$REPO_ROOT/variants/base/setups/hex--install.sh"


# Stub: a `mix` (on ELIXIR_HOME/bin, which the script prepends to PATH) that
# echoes the command it was asked to run.
STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin"

cat > "$STUB/bin/mix" << 'EOF'
#!/bin/bash
echo "STUB_MIX $*"
EOF
chmod +x "$STUB/bin/mix"

run_hex_install() {
    ELIXIR_HOME="$STUB" MIX_HOME="$STUB" HEX_HOME="$STUB" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$HEX_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

assert_emits() {
    local num="$1" desc="$2" expected="$3"; shift 3
    local out
    out=$(run_hex_install "$@")
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

# 1. Plain package → no version argument.
assert_emits 1 "plain package installs without a version" \
    "archive.install hex phx_new --force" phx_new

# 2. Pinned package → version as a positional arg before --force.
assert_emits 2 "@version becomes mix's positional version arg" \
    "archive.install hex phx_new 1.7.0 --force" phx_new@1.7.0

# 3. Comma list → split per package, version pinning preserved per item.
assert_emits 3 "comma list: pinned item keeps its version" \
    "archive.install hex phx_new 1.7.0 --force" phx_new@1.7.0,ecto
assert_emits 4 "comma list: unpinned item installs latest" \
    "archive.install hex ecto --force" phx_new@1.7.0,ecto

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
