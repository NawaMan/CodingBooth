#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: luarocks--install.sh command emission
#
# Runs the real luarocks--install.sh with `luarocks` stubbed, and asserts the
# `luarocks install` command line it emits. This locks in the
# name@version → positional-version translation (LuaRocks takes the version as
# a positional argument) and the per-rock splitting of comma lists.
#
# The script requires root and an installed luarocks; we satisfy those with
# a faked EUID + a LUA_HOME override pointing at a stub, so nothing real runs.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LUAROCKS_SCRIPT="$REPO_ROOT/variants/base/setups/luarocks--install.sh"


# Stub: a `luarocks` at LUA_HOME/bin/luarocks (the absolute path the script
# builds) that echoes the command it was asked to run.
STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin"

cat > "$STUB/bin/luarocks" << 'EOF'
#!/bin/bash
echo "STUB_LUAROCKS $*"
EOF
chmod +x "$STUB/bin/luarocks"

run_luarocks_install() {
    LUA_HOME="$STUB" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$LUAROCKS_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

assert_emits() {
    local num="$1" desc="$2" expected="$3"; shift 3
    local out
    out=$(run_luarocks_install "$@")
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

# 1. Plain rock → no version argument.
assert_emits 1 "plain rock installs without a version" \
    "STUB_LUAROCKS install busted" busted

# 2. Pinned rock → version as a positional arg.
assert_emits 2 "@version becomes luarocks' positional version arg" \
    "STUB_LUAROCKS install busted 2.0.0" busted@2.0.0

# 3. Comma list → split per rock, version pinning preserved per item.
assert_emits 3 "comma list: pinned item keeps its version" \
    "STUB_LUAROCKS install busted 2.0.0" busted@2.0.0,luasocket
assert_emits 4 "comma list: unpinned item installs latest" \
    "STUB_LUAROCKS install luasocket" busted@2.0.0,luasocket

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
