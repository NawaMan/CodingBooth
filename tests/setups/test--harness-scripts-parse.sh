#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Every script the host's bash runs as a test, or as a test runner, parses.
#
# Two ways one has not, both found only by accident:
#
#  - macOS's /bin/bash is 3.2, and it reads a heredoc inside $( ) while looking
#    for the $( )'s close: a `case` pattern's bare `)` in the heredoc ends it
#    early. wrapper/081, 097 and 098 hit that and failed on every Mac (081 as
#    an unexplained missing file). The fix is `(pattern)`, with the leading
#    paren; this is what keeps the next one from going unnoticed.
#  - config/template/test11-tmpl-neovim.sh was committed as syntax-highlighted
#    terminal output — ANSI codes on every line — and parsed on no bash at all
#    for eight months, because nothing ran its suite.
#
# `bash -n` with the bash running this test, so a Mac checks 3.2 and Linux 5.x.
# Covered: everything under tests/, and each example's host side (.cb-tests
# tests other than inBooth-*, and its runner). inBooth-* scripts run in the
# booth's bash, not this one, and are left out. It lives with the setups tests
# because they are the host-side suite that needs no container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh
SELF="$SCRIPT_DIR/$(basename "$0")"   # $0 stops resolving after the cd below

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Paths a test run writes into its own folder — scratch projects, logs,
# installed wrappers, an example's build output — are not sources.
scripts=()
while IFS= read -r f; do
    scripts+=("$f")
done < <(
    {
        find tests -name '*.sh' -type f \
            -not -path '*/prj--*' -not -path '*/logs/*' -not -path '*/.booth/*' \
            -not -path '*/node_modules/*'
        find examples/workspaces -maxdepth 1 -name '*.sh' -type f
        find examples/workspaces -mindepth 2 -maxdepth 2 -name 'run-automatic-on-host-test.sh' -type f
        find examples/workspaces -mindepth 3 -maxdepth 3 -path '*/.cb-tests/*.sh' -type f \
            -not -name 'inBooth-*'
    } | LC_ALL=C sort
)

N=0
bad=()
for f in "${scripts[@]}"; do
    # A script with a non-bash shebang (zsh, python, …) is not this shell's to parse.
    first="$(head -n 1 "$f")"
    if [[ "$first" == '#!'* && "$first" != *bash* && "$first" != *'/sh'* ]]; then
        continue
    fi
    N=$((N + 1))
    # "$BASH", not `bash`: the one running this test, not whichever is first on PATH.
    if ! err="$("$BASH" -n "$f" 2>&1)"; then
        bad+=("$f")
        print_test_result "false" "$SELF" "${#bad[@]}" "$f should parse with bash ${BASH_VERSION%%(*}"
        printf '%s\n' "$err" | head -3 | sed 's/^/     /'
    fi
done

if [[ "$N" -lt 300 ]]; then
    print_test_result "false" "$SELF" "$((${#bad[@]} + 1))" "found only $N scripts to check — the search is broken, not the scripts"
    exit 1
fi
if [[ ${#bad[@]} -gt 0 ]]; then
    exit 1
fi
print_test_result "true" "$SELF" "1" "all $N host-side test scripts parse with bash ${BASH_VERSION%%(*}"
