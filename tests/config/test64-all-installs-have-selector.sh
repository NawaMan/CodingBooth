#!/bin/bash
# Guard: every <name>--install.sh backend must be reachable through `booth config`
# via a template that emits `install <name>`. Keeps the install backends and the
# config selectors in sync so all of them stay user-settable.
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
for script in "$root"/variants/base/setups/*--install.sh; do
    name="$(basename "$script" --install.sh)"
    grep -rqE "install ${name}( |\\\$)" "$root/templates" --include="*.toml"
    assert-true "$?" "${name} has a booth config selector"
done
finally
