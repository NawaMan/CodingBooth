#!/bin/bash
# Guard: every [params.X] a template declares must actually be referenced as
# ${X} somewhere in that template's directory.
#
# A declared-but-unreferenced param is invisible: `booth config` shows the knob,
# writes `arg X=<value>` into the Boothfile, and nothing consumes it — so the
# user's choice is silently dropped. That is exactly what a dropped
# `--version ${X_VERSION}` on a setup line looks like, and no other suite would
# notice. The sibling of test86, which guards `setup <name>` against a missing
# script.
#
# Scope is the template's directory, not the single file, because a parent
# template may declare a param its extensions consume (e.g. ollama declares
# OLLAMA_PORT; ollama/expose--extension.toml and autostart--extension.toml use
# it).
source "$(dirname "$0")/test-helpers--source.sh"

# Locate repo root (the directory that holds templates/ and variants/).
root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done

# assert-true <condition-result> <message>: pass when the first arg is "0".
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
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("Test ${TEST_COUNT}: ${message}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

begin
while IFS= read -r toml; do
    dir="$(dirname "$toml")"
    rel="${toml#"$root/templates/"}"
    while IFS= read -r param; do
        [[ -n "$param" ]] || continue
        grep -rqF -- "\${${param}}" "$dir"
        assert-true "$?" "${rel}: \${${param}} is used"
    done < <(grep -oE '^\[params\.[A-Z0-9_]+\]' "$toml" | sed 's/^\[params\.//; s/\]$//')
done < <(find "$root/templates" -name '*.toml' | sort)
finally
