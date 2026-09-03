#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: per-editor extension installs in libs/code-extension-source.sh
#
# Desktop VS Code and code-server resolve against different registries — the
# Microsoft Marketplace and Open VSX — with independent publisher namespaces. The
# same extension can carry a different id on each (ElixirLS is JakeBecker.elixir-ls
# on the Marketplace and elixir-lsp.elixir-ls on Open VSX), and an id present on one
# can be absent, or a different package entirely, on the other. So the lib offers
# three entry points, and this test pins which editor each one drives:
#
#   install_extensions             -> every editor found
#   install_vscode_extensions      -> `code` only, no-op without it
#   install_codeserver_extensions  -> `code-server` only, no-op without it
#
# Getting this wrong is silent: install_extensions warns and returns 0, so an id
# sent to the wrong editor yields a booth missing the extension and a green build.
# That is exactly how the elixir id went unnoticed, hence a test rather than trust.
#
# It also pins the post-install verification the lib does, which must match the id
# case-insensitively: real desktop VS Code lowercases the ids it reports, so the
# `code` stub below does too.
#
# Both CLIs are stubbed and both extension dirs redirected, so nothing real runs.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"
LIB="$SETUPS_DIR/libs/code-extension-source.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/ext-code" "$STUB/ext-code-server"

# Stub editor CLI: records each install into the extensions dir it was handed, so the
# test can tell which editor(s) a given call actually drove.
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
    # Attempts are counted so a test can see a retry happen. `flaky.*` stands in
    # for a registry that is down: it 503s for the first FLAKY_FAILS calls (0 by
    # default, so every other test sees an install that just works).
    N_FILE="$DIR/attempts-$ID.txt"
    N=$(cat "$N_FILE" 2>/dev/null || echo 0); N=$((N + 1)); echo "$N" > "$N_FILE"
    case "$ID" in
      flaky.*)
        if [ "$N" -le "${FLAKY_FAILS:-0}" ]; then
          echo "Error while installing extensions: Server returned 503" >&2
          exit 1
        fi
        ;;
    esac
    grep -qx "$ID" "$DB" || echo "$ID" >> "$DB"
    ;;
  list)    cat "$DB" ;;
esac
EOF
chmod +x "$STUB/bin/code-server"

# Desktop VS Code lowercases every id it reports from --list-extensions, while
# code-server hands back the publisher's own casing. That difference is not
# cosmetic: it is what the lib's verification has to survive, so the `code` stub
# reproduces it rather than echoing back what it was given. What it *records* stays
# verbatim, so the assertions below still read the id as it was asked for.
cat > "$STUB/bin/code" << 'EOF'
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
  install) grep -qx "$ID" "$DB" || echo "$ID" >> "$DB" ;;
  list)    tr '[:upper:]' '[:lower:]' < "$DB" ;;
esac
EOF
chmod +x "$STUB/bin/code"

ALL_PASSED=true
TEST_NUM=0

# run_lib <path-prefix> <shell-snippet>
#   Sources the real lib with both extension dirs redirected and PATH controlled,
#   then runs the snippet. path-prefix decides which CLIs are discoverable.
run_lib() {
    local path_prefix="$1"; shift
    rm -f "$STUB/ext-code/installed.txt" "$STUB/ext-code-server/installed.txt"
    rm -f "$STUB"/ext-code/attempts-*.txt "$STUB"/ext-code-server/attempts-*.txt
    PATH="${path_prefix}:/usr/bin:/bin" \
    HOME="$STUB" \
    VSCODE_EXTENSION_DIR="$STUB/ext-code" \
    CODESERVER_EXTENSION_DIR="$STUB/ext-code-server" \
    FLAKY_FAILS="${FLAKY_FAILS:-0}" \
    CB_RETRY_DELAY=0 \
        bash -c "source '$LIB'; $*" > "$STUB/out.txt" 2>&1 || true
}

lib_output() { cat "$STUB/out.txt" 2>/dev/null || true; }

installed_in() {  # installed_in code|code-server
    local dir="$STUB/ext-code"
    [[ "$1" == "code-server" ]] && dir="$STUB/ext-code-server"
    cat "$dir/installed.txt" 2>/dev/null || true
}

# assert_lands <desc> <call> <expect-in-code> <expect-in-code-server>
#   Expectations are the exact id, or "" for "nothing should land here".
assert_lands() {
    local desc="$1" call="$2" want_code="$3" want_cs="$4"
    TEST_NUM=$((TEST_NUM + 1))
    run_lib "$STUB/bin" "$call"
    local got_code got_cs
    got_code="$(installed_in code)"
    got_cs="$(installed_in code-server)"
    if [[ "$got_code" == "$want_code" && "$got_cs" == "$want_cs" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        echo "  call:     $call"
        echo "  expected: code='${want_code}' code-server='${want_cs}'"
        echo "  actual:   code='${got_code}' code-server='${got_cs}'"
        ALL_PASSED=false
    fi
}

# 1. install_extensions still drives both — the pre-existing contract, unchanged by
#    the refactor that introduced the per-editor variants.
assert_lands "install_extensions drives both editors" \
    "install_extensions shared.ext" "shared.ext" "shared.ext"

# 2-3. The per-editor variants drive exactly one, leaving the other untouched.
assert_lands "install_vscode_extensions drives only code" \
    "install_vscode_extensions ms.only" "ms.only" ""
assert_lands "install_codeserver_extensions drives only code-server" \
    "install_codeserver_extensions ovsx.only" "" "ovsx.only"

# 4. The elixir shape: a different id per registry, each landing in its own editor.
#    JakeBecker on Open VSX is a 404 and elixir-lsp on the Marketplace is a
#    DEPRECATED stub, so crossing these over is worse than installing nothing.
assert_lands "per-editor ids do not cross over" \
    "install_codeserver_extensions elixir-lsp.elixir-ls; install_vscode_extensions JakeBecker.elixir-ls" \
    "JakeBecker.elixir-ls" "elixir-lsp.elixir-ls"

# 5-6. On a single-editor image the variant for the absent editor is a quiet no-op,
#      not an error — the codeserver variant has no `code`, the desktop variants no
#      code-server, and neither should fail a build over an id meant for the other.
mkdir -p "$STUB/bin-cs-only" && cp "$STUB/bin/code-server" "$STUB/bin-cs-only/"
TEST_NUM=$((TEST_NUM + 1))
run_lib "$STUB/bin-cs-only" "install_vscode_extensions ms.only"
if [[ -z "$(installed_in code)" && -z "$(installed_in code-server)" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "vscode-only ids are skipped when code is absent"
else
    print_test_result "false" "$0" "$TEST_NUM" "vscode-only ids should be skipped when code is absent"
    ALL_PASSED=false
fi

mkdir -p "$STUB/bin-code-only" && cp "$STUB/bin/code" "$STUB/bin-code-only/"
TEST_NUM=$((TEST_NUM + 1))
run_lib "$STUB/bin-code-only" "install_codeserver_extensions ovsx.only"
if [[ -z "$(installed_in code)" && -z "$(installed_in code-server)" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "codeserver-only ids are skipped when code-server is absent"
else
    print_test_result "false" "$0" "$TEST_NUM" "codeserver-only ids should be skipped when code-server is absent"
    ALL_PASSED=false
fi

# 7. install_extensions on a single-editor image still installs into the one present
#    (the codeserver-variant path every curated setup takes).
TEST_NUM=$((TEST_NUM + 1))
run_lib "$STUB/bin-cs-only" "install_extensions shared.ext"
if [[ "$(installed_in code-server)" == "shared.ext" && -z "$(installed_in code)" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "install_extensions installs into the one editor present"
else
    print_test_result "false" "$0" "$TEST_NUM" "install_extensions should install into the one editor present"
    echo "  actual: code='$(installed_in code)' code-server='$(installed_in code-server)'"
    ALL_PASSED=false
fi

# 8. A mixed-case id verifies on `code`. VS Code lowercases what it lists, so a
#    case-sensitive match reported "Not found after install: JakeBecker.elixir-ls"
#    on the line after announcing the install had succeeded — for every mixed-case
#    id in the catalog, of which there are plenty (Dart-Code.dart-code,
#    REditorSupport.r, JakeBecker.elixir-ls). Nothing was actually broken, which is
#    the problem: a warning that cries wolf on a healthy build trains you to skip
#    the one that matters.
TEST_NUM=$((TEST_NUM + 1))
run_lib "$STUB/bin-code-only" "install_vscode_extensions JakeBecker.elixir-ls"
if grep -q "Verified: JakeBecker.elixir-ls" <<< "$(lib_output)" \
   && ! grep -q "Not found after install" <<< "$(lib_output)"; then
    print_test_result "true" "$0" "$TEST_NUM" "a mixed-case id verifies rather than warning"
else
    print_test_result "false" "$0" "$TEST_NUM" "a mixed-case id should verify rather than warning"
    echo "  actual output: $(lib_output)"
    ALL_PASSED=false
fi

# 9. ...and verification is not thereby made vacuous: an id that never lands still
#    warns. This is the check that caught the elixir bug in the first place, so
#    loosening the match must not cost it.
mkdir -p "$STUB/bin-noop"
cat > "$STUB/bin-noop/code" << 'STUBEOF'
#!/bin/bash
# Accepts the install, records nothing — an id that resolves and then isn't there.
exit 0
STUBEOF
chmod +x "$STUB/bin-noop/code"

TEST_NUM=$((TEST_NUM + 1))
run_lib "$STUB/bin-noop" "install_vscode_extensions Ghost.Vanishes"
if grep -q "Not found after install: Ghost.Vanishes" <<< "$(lib_output)"; then
    print_test_result "true" "$0" "$TEST_NUM" "an id that never lands still warns"
else
    print_test_result "false" "$0" "$TEST_NUM" "an id that never lands should still warn"
    echo "  actual output: $(lib_output)"
    ALL_PASSED=false
fi

# 10. A transient registry error is retried here too. This path only *warns* on a
#     failed install, so an unretried 503 hands back a booth quietly missing the
#     extension and a green build — the failure mode this whole file exists to
#     guard against. A Marketplace 503 really did fail five consecutive image
#     builds of tests/complex/test-boothfile-code-extension; on that path the
#     build stopped, on this one it would not have.
TEST_NUM=$((TEST_NUM + 1))
FLAKY_FAILS=1
run_lib "$STUB/bin-cs-only" "install_codeserver_extensions flaky.ext"
FLAKY_FAILS=0
if [[ "$(installed_in code-server)" == "flaky.ext" ]] \
   && grep -q "Verified: flaky.ext" <<< "$(lib_output)" \
   && ! grep -q "Failed to install" <<< "$(lib_output)"; then
    print_test_result "true" "$0" "$TEST_NUM" "a transient 503 is retried rather than warned past"
else
    print_test_result "false" "$0" "$TEST_NUM" "a transient 503 should be retried rather than warned past"
    echo "  actual: code-server='$(installed_in code-server)'"
    echo "$(lib_output)" | sed 's/^/          /'
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
