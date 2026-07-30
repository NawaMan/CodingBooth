#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: code-extension--install.sh
#
# Runs the real code-extension--install.sh with `code` and `code-server` stubbed,
# and asserts both what it emits and — the point of this script — what it does
# when an install goes wrong. Unlike the curated `<lang>-code-extension--setup.sh`
# scripts, which log a warning and carry on, this one names the extension the user
# asked for explicitly, so a bad id must fail the build rather than hand back an
# image quietly missing it.
#
# Locked in here:
#   - comma-separated ids are split
#   - a trailing @version is passed through, and verification matches the bare id
#   - an install that errors is a hard failure
#   - an install that "succeeds" but never lands is also a hard failure
#   - no editor in the image is a hard failure, not a silent skip
#
# The script requires root; we satisfy that with fakeroot, and point both
# extension dirs at a temp tree so nothing real is touched.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"
EXT_SCRIPT="$SETUPS_DIR/code-extension--install.sh"

# The script guards on EUID==0; run under fakeroot when not already root.
ROOT_RUN=()
if [ "$EUID" -ne 0 ]; then
    if command -v fakeroot >/dev/null 2>&1; then
        ROOT_RUN=(fakeroot)
    else
        echo "SKIP: needs root or fakeroot to satisfy code-extension--install.sh's root check"
        exit 0
    fi
fi

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/ext-code" "$STUB/ext-code-server" "$STUB/home"

# Stub editor CLI, standing in for both `code` and `code-server`. It keeps an
# installed-ids file per extensions dir so --list-extensions reflects what
# --install-extension actually did, which is what the script verifies against.
#   bogus.*  → install fails outright (id not on the registry)
#   ghost.*  → install reports success but the id never lands
cat > "$STUB/bin/code-server" << 'EOF'
#!/bin/bash
DIR=""; ACT=""; ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --extensions-dir)    DIR="$2"; shift 2 ;;
    --install-extension) ACT=install; ID="$2"; shift 2 ;;
    --list-extensions)   ACT=list; shift ;;
    *) shift ;;
  esac
done
DB="$DIR/installed.txt"; touch "$DB"
case "$ACT" in
  install)
    base="${ID%@*}"
    case "$base" in
      bogus.*) echo "Extension '$base' not found." >&2; exit 1 ;;
      ghost.*) echo "STUB_INSTALL $ID"; exit 0 ;;
    esac
    grep -qx "$base" "$DB" || echo "$base" >> "$DB"
    echo "STUB_INSTALL $ID"
    ;;
  list) cat "$DB" ;;
esac
EOF
chmod +x "$STUB/bin/code-server"
cp "$STUB/bin/code-server" "$STUB/bin/code"

run_ext_install() {
    # PATH is stubbed so the script finds the fake CLIs, never a real editor on
    # the host. SETUP_LIBS_DIR points at the repo's lib, which is the real one.
    PATH="$STUB/bin:$PATH" \
    HOME="$STUB/home" \
    SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
    VSCODE_EXTENSION_DIR="$STUB/ext-code" \
    CODESERVER_EXTENSION_DIR="$STUB/ext-code-server" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$EXT_SCRIPT" "$@" 2>&1
}

# Same, but with an empty PATH prefix so neither editor is found.
run_ext_install_no_editor() {
    PATH="$STUB/empty:/usr/bin:/bin" \
    HOME="$STUB/home" \
    SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
    VSCODE_EXTENSION_DIR="$STUB/ext-code" \
    CODESERVER_EXTENSION_DIR="$STUB/ext-code-server" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$EXT_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true
TEST_NUM=0

# Asserts the run succeeds and its output contains $expected.
assert_ok() {
    local desc="$1" expected="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    local out rc
    out=$(run_ext_install "$@") && rc=0 || rc=$?
    if [[ $rc -eq 0 ]] && echo "$out" | grep -qF -- "$expected"; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        echo "  args:     $*"
        echo "  expected: exit 0 and output containing: $expected"
        echo "  actual:   exit $rc"
        echo "$out" | sed 's/^/            /'
        ALL_PASSED=false
    fi
}

# Asserts the run fails and its output contains $expected.
assert_fails() {
    local desc="$1" expected="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    local out rc
    out=$(run_ext_install "$@") && rc=0 || rc=$?
    if [[ $rc -ne 0 ]] && echo "$out" | grep -qF -- "$expected"; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        echo "  args:     $*"
        echo "  expected: non-zero exit and output containing: $expected"
        echo "  actual:   exit $rc"
        echo "$out" | sed 's/^/            /'
        ALL_PASSED=false
    fi
}

# 1-2. A single id installs and is verified against the installed list.
assert_ok "single id installs" "STUB_INSTALL elixir-lsp.elixir-ls" elixir-lsp.elixir-ls
assert_ok "single id is verified after install" "✔ elixir-lsp.elixir-ls" elixir-lsp.elixir-ls

# 3-4. A comma list is split into separate ids (the form the config template emits).
assert_ok "comma list: first id installed" \
    "STUB_INSTALL elixir-lsp.elixir-ls" "elixir-lsp.elixir-ls,ms-python.python"
assert_ok "comma list: second id installed" \
    "STUB_INSTALL ms-python.python" "elixir-lsp.elixir-ls,ms-python.python"

# 5-6. @version is handed to --install-extension verbatim; verification strips it,
#      because --list-extensions reports the bare id.
assert_ok "@version passed through to --install-extension" \
    "STUB_INSTALL eamodio.gitlens@15.6.0" eamodio.gitlens@15.6.0
assert_ok "@version verified against the bare id" \
    "✔ eamodio.gitlens@15.6.0" eamodio.gitlens@15.6.0

# 7-8. A failed install is a build failure, with the Open VSX hint.
assert_fails "failed install exits non-zero" "Failed to install: bogus.nope" bogus.nope
assert_fails "failed install points at Open VSX" "open-vsx.org" bogus.nope

# 9. An install that claims success but never lands is caught by the verify step.
assert_fails "install that never lands is caught" \
    "Not found after install: ghost.vanishes" ghost.vanishes

# 10. One bad id in a list fails the whole run — a partially-applied image is
#     worse than a build that stops.
assert_fails "one bad id in a list fails the run" \
    "Failed to install: bogus.nope" "elixir-lsp.elixir-ls,bogus.nope"

# 11. No arguments → no-op, zero exit. CODE_EXT_PKGS defaults to "" in
#     templates/ides/code-ext-pkg, so `install code-extension ${CODE_EXT_PKGS}`
#     reaches here with no ids whenever that template is selected without naming
#     any, and a hard failure would break the image build. Naming nothing is not
#     the same as naming something broken: an unresolvable id is still a hard
#     error (tests 7-10), as is a missing editor (test 12).
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_ext_install) && RC=0 || RC=$?
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -qF "nothing to install"; then
    print_test_result "true" "$0" "$TEST_NUM" "no arguments is a no-op"
else
    print_test_result "false" "$0" "$TEST_NUM" "no arguments is a no-op"
    echo "  actual: exit $RC"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

# 12. No editor in the image → hard failure with an actionable message, rather
#     than the silent skip the curated per-language setups do.
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_ext_install_no_editor elixir-lsp.elixir-ls) && RC=0 || RC=$?
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qF "Neither code-server nor VS Code is installed"; then
    print_test_result "true" "$0" "$TEST_NUM" "no editor installed is a hard failure"
else
    print_test_result "false" "$0" "$TEST_NUM" "no editor installed is a hard failure"
    echo "  actual: exit $RC"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
