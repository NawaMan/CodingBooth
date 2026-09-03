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
# The script requires root; we satisfy that with a faked EUID, and point both
# extension dirs at a temp tree so nothing real is touched.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"
EXT_SCRIPT="$SETUPS_DIR/code-extension--install.sh"


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
    # Every attempt is counted, per id and per extensions dir, so a test can assert
    # how many times the script retried a given install.
    N_FILE="$DIR/attempts-$base.txt"
    N=$(cat "$N_FILE" 2>/dev/null || echo 0); N=$((N + 1)); echo "$N" > "$N_FILE"
    case "$base" in
      bogus.*) echo "Extension '$base' not found." >&2; exit 1 ;;
      ghost.*) echo "STUB_INSTALL $ID"; exit 0 ;;
      flaky.*)
        # The registry is down for the first FLAKY_FAILS attempts, then recovers.
        if [ "$N" -le "${FLAKY_FAILS:-1}" ]; then
          echo "Error while installing extensions: Server returned 503" >&2
          exit 1
        fi
        ;;
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
    FLAKY_FAILS="${FLAKY_FAILS:-1}" \
    CB_RETRY_ATTEMPTS="${CB_RETRY_ATTEMPTS:-3}" \
    CB_RETRY_DELAY=0 \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$EXT_SCRIPT" "$@" 2>&1
}

# Attempt counts and installed lists persist in the stub dirs; clear them so each
# retry test starts from a registry that has not been called yet.
reset_stub_state() {
    rm -f "$STUB"/ext-code/attempts-*.txt "$STUB"/ext-code-server/attempts-*.txt
    rm -f "$STUB"/ext-code/installed.txt "$STUB"/ext-code-server/installed.txt
}

# How many times the stub was asked to install $1 into desktop VS Code's dir.
attempts_for() {
    cat "$STUB/ext-code/attempts-$1.txt" 2>/dev/null || echo 0
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

# ── Retrying a transient registry error ──────────────────────────────────────
# `--install-extension` talks to a registry mid-build, and neither CLI retries. A
# Marketplace 503 once failed five consecutive image builds of
# tests/complex/test-boothfile-code-extension while the Open VSX half of the same
# run succeeded every time. cb_retry (libs/retry-source.sh)
# retries those, and only those: a rejected id must still fail on the first call,
# or every typo'd id costs the build the full backoff before saying so.

# 13-14. A 503 that clears on the second attempt installs, and says it retried.
reset_stub_state
FLAKY_FAILS=1
assert_ok "a transient 503 is retried and the install succeeds" \
    "✔ flaky.ext" flaky.ext
reset_stub_state
assert_ok "the retry is reported" "retrying in" flaky.ext

# 15. Two failures still clear, because the default is three attempts.
reset_stub_state
FLAKY_FAILS=2
assert_ok "two transient 503s still clear inside the attempt budget" \
    "✔ flaky.ext" flaky.ext

# 16. The retry is bounded: a registry that never recovers fails the build after
#     CB_RETRY_ATTEMPTS calls, not forever.
reset_stub_state
FLAKY_FAILS=99
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_ext_install flaky.ext) && RC=0 || RC=$?
N=$(attempts_for flaky.ext)
if [[ $RC -ne 0 ]] && [[ "$N" == "3" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "a registry that never recovers fails after 3 attempts"
else
    print_test_result "false" "$0" "$TEST_NUM" "a registry that never recovers fails after 3 attempts"
    echo "  expected: non-zero exit after exactly 3 attempts"
    echo "  actual:   exit $RC after $N attempts"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi
FLAKY_FAILS=1

# 17. A rejected id is NOT retried — it reads the same on every attempt, so the
#     hard error stays immediate.
reset_stub_state
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_ext_install bogus.nope) && RC=0 || RC=$?
N=$(attempts_for bogus.nope)
if [[ $RC -ne 0 ]] && [[ "$N" == "1" ]] && ! echo "$OUT" | grep -qF "retrying in"; then
    print_test_result "true" "$0" "$TEST_NUM" "a rejected id fails on the first attempt, unretried"
else
    print_test_result "false" "$0" "$TEST_NUM" "a rejected id fails on the first attempt, unretried"
    echo "  expected: non-zero exit after exactly 1 attempt, with no retry notice"
    echo "  actual:   exit $RC after $N attempts"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

# 18. Nor is an install that reports success but never lands: the verify step
#     catches it, and re-running the install would not change the outcome.
reset_stub_state
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_ext_install ghost.vanishes) && RC=0 || RC=$?
N=$(attempts_for ghost.vanishes)
if [[ $RC -ne 0 ]] && [[ "$N" == "1" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "an install that never lands is not retried"
else
    print_test_result "false" "$0" "$TEST_NUM" "an install that never lands is not retried"
    echo "  expected: non-zero exit after exactly 1 attempt"
    echo "  actual:   exit $RC after $N attempts"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

reset_stub_state

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
