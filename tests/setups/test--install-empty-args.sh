#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: *--install.sh no-op on an empty package list
#
# Every *-pkg template emits `install <mgr> ${..._PKGS}` with the package list
# defaulting to empty, so an install script that treats "no packages" as a usage
# error fails the image build of every project that selects the extension without
# naming packages. Each install script must therefore exit 0 and install nothing.
#
# The scripts are run for real, under fakeroot, with every package manager
# stubbed by a recorder on PATH. A stub that gets invoked appends to a marker
# file, so "installed nothing" is asserted directly rather than inferred from the
# exit code. Nothing real is installed and the host is untouched.
#
# The assertion targets install *commands*, not any use of the binary: some
# scripts legitimately probe unconditionally (conan--install.sh runs
# `conan --version` to report readiness), which installs nothing.
#
# The manager list is discovered from variants/base/setups/, so a newly added
# install script is covered without editing this test.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"

# The scripts guard on EUID==0. Run under fakeroot when we are not root.
ROOT_RUN=()
if [ "$EUID" -ne 0 ]; then
    if command -v fakeroot >/dev/null 2>&1; then
        ROOT_RUN=(fakeroot)
    else
        echo "SKIP: needs root or fakeroot to satisfy the install scripts' root check"
        exit 0
    fi
fi

STUB=$(mktemp -d)
MARKER="$STUB/invoked.log"
trap "rm -rf $STUB" EXIT

# Recorders for every command an install script might shell out to. Each logs the
# call and succeeds, so reaching one is observable instead of fatal.
STUBBED_COMMANDS=(
    apt-get brew bun cabal cargo code-server conan conda deno dotnet gem go
    luarocks mix npm pecl pip pip3 python python3 sudo uv yarn
)
for cmd in "${STUBBED_COMMANDS[@]}"; do
    cat > "$STUB/$cmd" << EOF
#!/bin/bash
echo "$cmd \$*" >> "$MARKER"
exit 0
EOF
    chmod +x "$STUB/$cmd"
done

# Run an install script with the stubs in front of PATH. Absolute-path probes are
# pointed at the stubs too, so no script can reach a real package manager.
run_install() {
    local script="$1"; shift
    PATH="$STUB:$PATH" \
    CARGO_BIN="$STUB/cargo" \
    LUA_HOME="$STUB/luahome" \
    MIX_HOME="$STUB/mixhome" \
    ELIXIR_HOME="$STUB/elixirhome" \
    SETUP_LIBS_DIR="$STUB/libs" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$script" "$@" 2>&1
}

ALL_PASSED=true
TEST_NUM=0

# An install-issuing invocation, as opposed to a version/readiness probe.
INSTALL_VERB='(^|[[:space:]])(install|add|download|archive\.install)([[:space:]]|$)|--install-extension'

# Assert: empty input exits 0 and issues no install command.
assert_noop() {
    local mgr="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))

    : > "$MARKER"
    local out exit_code=0
    out=$(run_install "$SETUPS_DIR/${mgr}--install.sh" "$@") || exit_code=$?

    local ok=true detail=""
    if [ "$exit_code" -ne 0 ]; then
        ok=false
        detail="exit=$exit_code"
    elif grep -qE "$INSTALL_VERB" "$MARKER" 2>/dev/null; then
        ok=false
        detail="installed: $(grep -E "$INSTALL_VERB" "$MARKER" | tr '\n' ';')"
    fi

    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$mgr: $desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$mgr: $desc ($detail)"
        echo "$out" | sed 's/^/      /' | head -5
        ALL_PASSED=false
    fi
}

# Assert: a real package DOES reach its package manager, so the no-op guard has
# not degenerated into "never install anything".
assert_installs() {
    local mgr="$1" desc="$2" expected="$3"; shift 3
    TEST_NUM=$((TEST_NUM + 1))

    : > "$MARKER"
    local out exit_code=0
    out=$(run_install "$SETUPS_DIR/${mgr}--install.sh" "$@") || exit_code=$?

    if grep -qF -- "$expected" "$MARKER" 2>/dev/null; then
        print_test_result "true" "$0" "$TEST_NUM" "$mgr: $desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" \
            "$mgr: $desc (expected '$expected'; exit=$exit_code)"
        echo "   invoked: $(tr '\n' ';' < "$MARKER" 2>/dev/null)"
        echo "$out" | sed 's/^/      /' | head -5
        ALL_PASSED=false
    fi
}

# ---- Every install script no-ops on an empty list -------------------------

MANAGERS=()
for script in "$SETUPS_DIR"/*--install.sh; do
    mgr=$(basename "$script")
    MANAGERS+=("${mgr%--install.sh}")
done

if [ ${#MANAGERS[@]} -eq 0 ]; then
    echo "❌ No *--install.sh scripts found in $SETUPS_DIR"
    exit 1
fi

for mgr in "${MANAGERS[@]}"; do
    assert_noop "$mgr" "no arguments is a no-op"
    assert_noop "$mgr" "an empty argument is a no-op" ""
    assert_noop "$mgr" "a comma-only list is a no-op" ",,"
done

# ---- cargo: flags without crates is also a no-op --------------------------
# `install cargo --locked ${CARGO_PKGS}` with an empty CARGO_PKGS reaches the
# script with only the flag, which must not fail the build either.
assert_noop "cargo" "flags without crates is a no-op" "--locked"
assert_noop "cargo" "flags with a comma-only list is a no-op" "--locked" ",,"

# ---- Negative control: real packages still install -----------------------
assert_installs "npm"   "a real package still installs" "npm install -g somepkg" "somepkg"
assert_installs "yarn"  "a real package still installs" "yarn global add somepkg" "somepkg"
assert_installs "cargo" "a real crate still installs"   "ripgrep"                 "ripgrep"
assert_installs "cargo" "flags plus a crate still installs" "ripgrep" "--locked" "ripgrep"

TEST_NUM=$((TEST_NUM + 1))
print_test_result "true" "$0" "$TEST_NUM" "checked ${#MANAGERS[@]} install scripts"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
