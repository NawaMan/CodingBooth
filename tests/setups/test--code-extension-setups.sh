#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: every *-code-extension--setup.sh runs and installs something
#
# Runs each curated extension setup for real, with `code` and `code-server`
# stubbed and both extension dirs redirected, and asserts:
#   1. it exits 0
#   2. it installed at least one extension id somewhere
#
# Why this shape. These setups are the one place a mistake is invisible: the
# install path warns and returns 0, and the setups are auto-selected, so a script
# that silently installs nothing still yields a green build. Two real bugs of that
# kind were found in one day — elixir asking for a Marketplace id on Open VSX, and
# fsharp's template naming a setup script that did not exist. Running each script
# and checking something came out is the cheapest guard that generalises.
#
# It is deliberately data-driven over the whole directory: add a setup and it is
# covered with no edit here.
#
# What this canNOT check is whether an id resolves on a real registry — the CLIs
# are stubs and accept anything. Registry checks need network and live in the
# authoring guidance (templates/README.md). What it does check is that the script
# runs, finds the lib, and reaches an install call with a non-empty id.
#
# The per-editor routing (which ids go to `code` vs `code-server`) is pinned
# separately in test--code-extension-per-editor.sh.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"


STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/ext-code" "$STUB/ext-code-server" "$STUB/home"

# Stub editor CLI accepting any id, recording installs per extensions dir.
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
  install) grep -qx "$ID" "$DB" || echo "$ID" >> "$DB" ;;
  list)    cat "$DB" ;;
esac
EOF
chmod +x "$STUB/bin/code-server"
cp "$STUB/bin/code-server" "$STUB/bin/code"

# One setup packs its extension with `zip`, which every booth image has and a
# host may not (Windows does not). What this file checks is that each script
# runs and reaches an install call with a real id, not what is inside the
# archive, so a stub that just creates the file it was asked for is enough — in
# the same spirit as the editor CLIs above. Used only when the host has no zip,
# so a host that does keeps exercising the real thing. Asked on the PATH the
# scripts run with below: a zip elsewhere on the caller's PATH (GnuWin32 on
# Windows) is one they never see.
if ! PATH="/usr/bin:/bin" command -v zip >/dev/null 2>&1; then
    cat > "$STUB/bin/zip" << 'EOF'
#!/bin/bash
# zip [-qr] <archive> <paths…> — the archive is all this has to produce.
for arg in "$@"; do
  case "$arg" in
    -*) ;;
    *) : > "$arg"; exit 0 ;;
  esac
done
exit 0
EOF
    chmod +x "$STUB/bin/zip"
fi

ALL_PASSED=true
TEST_NUM=0
CHECKED=0

for script in "$SETUPS_DIR"/*-code-extension--setup.sh; do
    name="$(basename "$script")"
    CHECKED=$((CHECKED + 1))

    : > "$STUB/ext-code/installed.txt"
    : > "$STUB/ext-code-server/installed.txt"

    out=$(PATH="$STUB/bin:/usr/bin:/bin" \
          HOME="$STUB/home" \
          SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
          VSCODE_EXTENSION_DIR="$STUB/ext-code" \
          CODESERVER_EXTENSION_DIR="$STUB/ext-code-server" \
          CB_WEB_PREVIEW_DIR="$STUB/web-preview" \
              ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$script" 2>&1) && rc=0 || rc=$?

    installed="$(cat "$STUB/ext-code/installed.txt" "$STUB/ext-code-server/installed.txt" 2>/dev/null | sort -u | tr '\n' ' ')"
    installed="${installed% }"

    TEST_NUM=$((TEST_NUM + 1))
    if [[ $rc -eq 0 && -n "$installed" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "${name%--setup.sh}: installs [${installed}]"
    else
        print_test_result "false" "$0" "$TEST_NUM" "${name%--setup.sh}: should run and install at least one id"
        echo "  exit:      $rc"
        echo "  installed: '${installed}'"
        echo "$out" | sed 's/^/             /' | tail -15
        ALL_PASSED=false
    fi
done

# Guard the guard — a glob that matches nothing would pass vacuously.
TEST_NUM=$((TEST_NUM + 1))
if [[ "$CHECKED" -ge 30 ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "checked $CHECKED extension setups"
else
    print_test_result "false" "$0" "$TEST_NUM" "expected >= 30 extension setups, found $CHECKED"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
