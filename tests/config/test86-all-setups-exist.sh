#!/bin/bash
# Guard: every `setup <name>` a template emits must have a matching
# variants/base/setups/<name>--setup.sh. A template naming a setup that does not
# exist scaffolds a Boothfile that cannot build, and nothing else catches it
# until someone runs that exact template. The mirror image of test64, which
# guards the other direction for install backends.
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

# Every distinct setup name referenced from a template's Boothfile segment.
# Skips names that are themselves a ${VAR} placeholder — those resolve per-param,
# not to a fixed script.
names="$(grep -rhoE '^[[:space:]]*setup +[A-Za-z0-9_.-]+' "$root/templates" --include="*.toml" \
         | awk '{print $2}' | sort -u)"

begin
for name in $names; do
    [[ -f "$root/variants/base/setups/${name}--setup.sh" ]]
    assert-true "$?" "template setup '${name}' has a setup script"
done
finally
