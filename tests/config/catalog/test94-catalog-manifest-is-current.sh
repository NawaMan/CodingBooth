#!/bin/bash
# Guard: every catalog item (setup, install, helper, lib, asset dir, template,
# extension) declares a valid cb-version, and build/catalog-manifest.tsv matches
# the tree. A stale manifest makes the next release's baseline lie about what
# shipped, and an item without a version cannot be checked for a missed bump.
# Whether a changed item was *bumped* is the release check's job
# (build/check-catalog-versions.sh), not this guard's. See
# docs/CATALOG_VERSIONING.md.
source "$(dirname "$0")/../test-helpers--source.sh"

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
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${message}")  # see test-helpers--source.sh assert-line's comment on the prefix
        echo -e "\033[31mFAILED\033[0m"
    fi
}

begin
out="$("$root/build/gen-catalog-manifest.sh" --check 2>&1)"
rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -E '^FAIL' | head -20
assert-true "$rc" "every catalog item has a cb-version; manifest is current"
finally
