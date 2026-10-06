#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Test: frameworks/* stay runtime-free and editor-only
#
# A framework does not pin its runtime — React runs on nodejs, bun or deno; Spring
# Boot on java or kotlin — so frameworks/* are top-level templates, not `+ext`s of a
# language, and must not `requires` one. This pins that:
#   1. Frameworks is a category, listed right after Languages
#   2. every framework template, selected alone, emits its
#      `setup <name>-code-extension` and no runtime setup
#   3. a framework beside a non-node runtime (react + bun) configures cleanly
#
# Data-driven over templates/frameworks/: a new framework is covered with no edit.
# No image is built.

source "$(dirname "$0")/../test-helpers--source.sh"

function assert-true() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="$1" message="$2"
    local width=64 label="${message} "
    local pad_len=$((width - ${#label})); (( pad_len < 3 )) && pad_len=3
    local pad; pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label}${pad} "
    if [[ "$ok" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1)); echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${message}")  # see test-helpers--source.sh assert-line's comment on the prefix
        echo -e "\033[31mFAILED\033[0m"
    fi
}

begin

# --- 1. Frameworks sits right after Languages ---------------------------------
booth template list --full > "$tmpfile" 2>&1
categories="$(grep -E '^[A-Z]' "$tmpfile" | grep -v '^Use ' | head -2 | tr '\n' '|')"
[[ "$categories" == "Languages|Frameworks|" ]]
assert-true "$?" "list --full: Frameworks follows Languages"

# --- 2. Each framework alone: its extension setup, no runtime -----------------
runtimes='^setup (nodejs|bun|deno|python|jdk|java|kotlin|go|ruby|php|dotnet)( |$)'
frameworks=0
for toml in "$_repo_root"/templates/frameworks/*/template.toml; do
    name="$(basename "$(dirname "$toml")")"
    frameworks=$((frameworks + 1))

    (cd "$prj" && run booth config --no-tui --overwrite --select "$name")
    boothfile="$prj/.booth/Boothfile"

    grep -qx "setup ${name}-code-extension" "$boothfile"
    assert-true "$?" "${name}: emits setup ${name}-code-extension"

    ! grep -qE "$runtimes" "$boothfile"
    assert-true "$?" "${name}: pulls in no runtime"

    ! grep -qE '^requires' "$toml"
    assert-true "$?" "${name}: declares no requires"
done

# A moved frameworks/ tree would empty the loop and pass with nothing checked.
(( frameworks >= 7 )); assert-true "$?" "frameworks examined (${frameworks} >= 7)"

# --- 3. React on bun, not node -------------------------------------------------
(cd "$prj" && run booth config --no-tui --overwrite --select bun --select react)
grep -qE '^setup bun( |$)' "$prj/.booth/Boothfile" &&
    grep -qx 'setup react-code-extension' "$prj/.booth/Boothfile" &&
    ! grep -qE '^setup nodejs( |$)' "$prj/.booth/Boothfile"
assert-true "$?" "react + bun: bun and react, no nodejs"

finally
