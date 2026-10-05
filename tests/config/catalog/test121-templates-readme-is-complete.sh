#!/bin/bash
# Guard: templates/README.md's Template Reference names every template, and
# names nothing that is gone.
#
# That reference is what an agent reads to pick a segment order band for a new
# template — "land in the same band as your neighbours". It is hand-curated, and
# it rotted both ways: half the catalogue (86 of 184 templates) never made it in,
# and five rows kept pointing at old paths after claude-code, codex, herdr and
# warp moved to ai-tools/ and ides/vscode stopped being a template at all.
#
#  1. Every templates/<category>/<name>/ appears as `<category>/<name>`.
#  2. Every `<category>/<name>` in the README is a real template directory, and
#     every `<parent>/<ext>--extension` a real extension file.
source "$(dirname "$0")/../test-helpers--source.sh"

# Locate repo root (the directory that holds templates/ and variants/).
root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done
readme="$root/templates/README.md"

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
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("${testname}: Test ${TEST_COUNT}: ${message}")  # see test-helpers--source.sh assert-line's comment on the prefix
        echo -e "\033[31mFAILED\033[0m"
    fi
}

begin

# --- 1. Every template directory is listed -----------------------------------
templates=0
for toml in "$root"/templates/*/*/template.toml; do
    dir="$(dirname "$toml")"
    path="$(basename "$(dirname "$dir")")/$(basename "$dir")"
    templates=$((templates + 1))

    grep -qF "\`${path}\`" "$readme"
    assert-true "$?" "README lists ${path}"
done

# A moved templates/ tree would empty the loop and pass with nothing checked.
(( templates >= 100 )); assert-true "$?" "templates examined (${templates} >= 100)"

# --- 2. Every path the README names still exists -----------------------------
#
# Only backticked `a/b` spans whose first part is a category (or, for
# extensions, whose second part ends in --extension) — the prose also mentions
# paths like `/etc/skel/Desktop` that are none of this test's business.
categories=" $(cd "$root/templates" && ls -d */ | tr -d '/' | tr '\n' ' ') "
named=0
while IFS= read -r span; do
    first="${span%%/*}" second="${span#*/}"
    if [[ "$second" == *--extension ]]; then
        named=$((named + 1))
        compgen -G "$root/templates/*/${first}/${second}.toml" > /dev/null
        assert-true "$?" "README's ${span} exists"
    elif [[ "$categories" == *" ${first} "* ]]; then
        named=$((named + 1))
        [[ -f "$root/templates/${first}/${second}/template.toml" ]]
        assert-true "$?" "README's ${span} exists"
    fi
done < <(grep -oE '`[a-z0-9-]+/[a-z0-9-]+`' "$readme" | tr -d '`' | sort -u)

(( named >= templates )); assert-true "$?" "README paths examined (${named} >= ${templates})"

finally
