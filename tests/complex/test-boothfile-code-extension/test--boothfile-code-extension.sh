#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile `install code-extension` — arbitrary editor extensions
#
# The escape hatch beside the curated `<lang>-code-extension--setup.sh` scripts:
# any Open VSX id, named directly. Verifies that:
#   1. code-extension is a recognized install manager (compiles to RUN ...)
#   2. The extension lands in the shared code-server extensions dir
#   3. code-server itself reports it as installed
#   4. It ALSO lands in desktop VS Code's separate extensions dir — the image has
#      both editors, and a booth may have either (code-server on the codeserver
#      variant, desktop VS Code on all four desktop variants)
#   5-7. The curated per-language path resolves too, and resolves *per registry*
#      (elixir, riding on the same image): code-server gets the Open VSX id,
#      desktop VS Code gets the Marketplace id, and the deprecated Marketplace fork
#      that shares the Open VSX id is nowhere to be found
#   8. A bogus id fails the build rather than producing an image quietly missing it
#
# Test 1 is docker-free (emit-dockerfile only). Tests 2-8 build a real image and
# run only when a locally-rebuilt base image is present, because
# code-extension--install.sh is new and not yet baked into the Docker Hub base image.
#
# Failure-mode coverage of the script itself (bad ids, @version pinning, comma
# splitting, no editor) is in tests/setups/test--code-extension-install.sh, which
# is hermetic and needs no build. This test is the end-to-end counterpart.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile install code-extension ==="

FAILED=0

EXT_ID="mads-hartmann.bash-ide-vscode"
# The two editors keep separate extension trees, and the install script must
# populate every one it finds — a booth gets code-server from the codeserver
# variant and desktop VS Code from the desktop variants, so neither dir may be
# assumed. Defaults come from libs/code-extension-source.sh.
EXT_DIR="/usr/local/share/code-server/extensions"
VSCODE_EXT_DIR="/usr/local/share/code/extensions"

# Locate the codingbooth binary for the docker-free emit-dockerfile check.
BOOTH_PATH=""
CHECK_DIR="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -f "$CHECK_DIR/codingbooth" && -x "$CHECK_DIR/codingbooth" ]]; then
        BOOTH_PATH="$CHECK_DIR/codingbooth"
        break
    fi
    CHECK_DIR="$(dirname "$CHECK_DIR")"
done
if [[ -z "$BOOTH_PATH" ]]; then
    echo "ERROR: Could not find codingbooth"
    exit 1
fi

DOCKERFILE=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" 2>&1) || true

# Test 1: install code-extension compiles to RUN code-extension--install.sh
if echo "$DOCKERFILE" | grep -qE "RUN code-extension--install\.sh ${EXT_ID}" \
   && ! echo "$DOCKERFILE" | grep -q "Unknown install script 'code-extension'"; then
    print_test_result "true" "$0" "1" "install code-extension compiles to RUN code-extension--install.sh"
else
    print_test_result "false" "$0" "1" "install code-extension should compile to RUN code-extension--install.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# The remaining tests build a real image, which needs code-extension--install.sh
# baked into the base image. That script is new and not yet on Docker Hub, so
# build against a locally-rebuilt base. Skip (reporting the emit result) when one
# isn't present.
use_local_base_image || exit $FAILED

# Test 2: the extension landed in the shared extensions dir
ACTUAL=$(run_coding_booth --silence-build -- "ls ${EXT_DIR} | grep -c '^${EXT_ID}-' || true" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" =~ ^[1-9] ]]; then
    print_test_result "true" "$0" "2" "extension directory exists under ${EXT_DIR}"
else
    print_test_result "false" "$0" "2" "extension directory should exist under ${EXT_DIR}"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: code-server reports it as installed (the check the install script makes)
ACTUAL=$(run_coding_booth --silence-build -- "code-server --extensions-dir ${EXT_DIR} --list-extensions 2>/dev/null" 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -qix "${EXT_ID}"; then
    print_test_result "true" "$0" "3" "code-server lists ${EXT_ID} as installed"
else
    print_test_result "false" "$0" "3" "code-server should list ${EXT_ID} as installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: the same run also populated desktop VS Code's separate extension tree.
# This is the half a codeserver-only check would miss: all four desktop variants
# ship `code` and no code-server, so an installer that only drove code-server would
# leave every desktop booth without the extension and still report success.
ACTUAL=$(run_coding_booth --silence-build -- "ls ${VSCODE_EXT_DIR} | grep -c '^${EXT_ID}-' || true" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" =~ ^[1-9] ]]; then
    print_test_result "true" "$0" "4" "extension also installed into ${VSCODE_EXT_DIR}"
else
    print_test_result "false" "$0" "4" "extension should also install into ${VSCODE_EXT_DIR}"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: the curated path resolves too, and resolves per registry. This rides along
# on the same image. The elixir setup originally asked for JakeBecker.elixir-ls — the
# Marketplace id, which 404s on Open VSX — and because install_extensions warns and
# carries on, it shipped a booth with no Elixir support and a green build. Only an
# assertion on the installed list catches that, so it lives here rather than in the
# elixir example, whose own test runs `--variant base` where the setup rightly skips.
ACTUAL=$(run_coding_booth --silence-build -- "code-server --extensions-dir ${EXT_DIR} --list-extensions 2>/dev/null" 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -qix "elixir-lsp.elixir-ls"; then
    print_test_result "true" "$0" "5" "code-server gets the Open VSX id elixir-lsp.elixir-ls"
else
    print_test_result "false" "$0" "5" "code-server should get the Open VSX id elixir-lsp.elixir-ls"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 6: desktop VS Code gets the *Marketplace* id for the same extension, and gets
# the real package. Presence alone is not enough here: elixir-lsp.elixir-ls also
# resolves on the Marketplace, as "ElixirLS Fork: DEPRECATED" v0.3.9999 — so an
# id-only assertion passes while the booth carries a dead stub. Pin the displayName.
#
# Match case-insensitively: VS Code lowercases the extension directory it writes, so
# JakeBecker.elixir-ls lands as jakebecker.elixir-ls-0.31.1. code-server preserves the
# publisher's casing, which is why the tests above can glob it directly.
ACTUAL=$(run_coding_booth --silence-build -- "find ${VSCODE_EXT_DIR} -maxdepth 1 -iname 'jakebecker.elixir-ls-*' -exec grep -hm1 displayName {}/package.json \\; 2>/dev/null" 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -qi "ElixirLS" && ! echo "$ACTUAL" | grep -qi "DEPRECATED"; then
    print_test_result "true" "$0" "6" "VS Code gets real ElixirLS via JakeBecker.elixir-ls, not the deprecated fork"
else
    print_test_result "false" "$0" "6" "VS Code should get real ElixirLS via JakeBecker.elixir-ls"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 7: and the deprecated stub is NOT installed under the Open VSX id. This is the
# regression guard proper — sending elixir-lsp.elixir-ls to both editors is what
# planted the stub in the desktop variants.
ACTUAL=$(run_coding_booth --silence-build -- "find ${VSCODE_EXT_DIR} -maxdepth 1 -iname 'elixir-lsp.elixir-ls-*' 2>/dev/null | wc -l" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "0" ]]; then
    print_test_result "true" "$0" "7" "the deprecated elixir-lsp fork is not installed into VS Code"
else
    print_test_result "false" "$0" "7" "the deprecated elixir-lsp fork should not be installed into VS Code"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 8: a bogus id fails the build. The curated per-language setups warn and
# carry on; this one must not, or a typo'd id yields an image silently missing
# the extension the user asked for.
BOGUS_DIR="$(mktemp -d)"
trap 'rm -rf "$BOGUS_DIR"' EXIT
mkdir -p "$BOGUS_DIR/.booth"
cp "$SCRIPT_DIR/.booth/config.toml" "$BOGUS_DIR/.booth/config.toml"
cat > "$BOGUS_DIR/.booth/Boothfile" << 'BOOTHFILE'
# syntax=codingbooth/boothfile:1
setup codeserver
install code-extension cb-no-such-publisher.cb-no-such-extension
BOOTHFILE

if "$BOOTH_PATH" --code "$BOGUS_DIR" --silence-build -- true >/dev/null 2>&1; then
    print_test_result "false" "$0" "8" "a bogus extension id should fail the build"
    FAILED=$((FAILED + 1))
else
    print_test_result "true" "$0" "8" "a bogus extension id fails the build"
fi

exit $FAILED
