#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: every *-code-extension--setup.sh skips cleanly without an editor
#
# Runs each curated extension setup with neither `code` nor `code-server` on
# PATH, and asserts:
#   1. it exits 0
#   2. it says it skipped (SKIP from skip_setup, or a "skipping" warning)
#
# Why this shape. These setups are auto-selected with their parent template
# (`terraform` brings `terraform+vscode-ext`), and the frameworks/* templates are
# nothing but one of them — so they land in base-variant booths that have no
# editor at all. There the right outcome is a skip, not a failed image build.
# `install code-extension` deliberately does fail without an editor; a setup
# written by copying that one instead of a sibling setup would break every
# base-variant booth that selects the parent.
#
# The install side is pinned in test--code-extension-setups.sh. Like that one,
# this is data-driven over the whole directory: add a setup and it is covered.
#
# PATH is a mirror of /usr/bin and /bin with `code` and `code-server` left out,
# not just "/usr/bin:/bin" — a host with VS Code installed has /usr/bin/code, and
# the guard (cb-has-vscode.sh) is a plain `command -v`.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"


STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/noeditor" "$STUB/home" "$STUB/ext-code" "$STUB/ext-code-server"

for dir in /bin /usr/bin; do
    for tool in "$dir"/*; do
        name="${tool##*/}"
        [[ "$name" == "code" || "$name" == "code-server" ]] && continue
        [[ -e "$STUB/noeditor/$name" || -L "$STUB/noeditor/$name" ]] || ln -s "$tool" "$STUB/noeditor/$name"
    done
done

ALL_PASSED=true
TEST_NUM=0
CHECKED=0

for script in "$SETUPS_DIR"/*-code-extension--setup.sh; do
    name="$(basename "$script")"
    CHECKED=$((CHECKED + 1))

    out=$(PATH="$STUB/noeditor" \
          HOME="$STUB/home" \
          SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
          VSCODE_EXTENSION_DIR="$STUB/ext-code" \
          CODESERVER_EXTENSION_DIR="$STUB/ext-code-server" \
          CB_WEB_PREVIEW_DIR="$STUB/web-preview" \
              ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$script" 2>&1) && rc=0 || rc=$?

    TEST_NUM=$((TEST_NUM + 1))
    if [[ $rc -eq 0 ]] && grep -qi "skip" <<< "$out"; then
        print_test_result "true" "$0" "$TEST_NUM" "${name%--setup.sh}: skips without an editor"
    else
        print_test_result "false" "$0" "$TEST_NUM" "${name%--setup.sh}: should exit 0 and say it skipped without an editor"
        echo "  exit: $rc"
        echo "$out" | sed 's/^/        /' | tail -10
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
