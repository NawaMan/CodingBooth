#!/bin/bash
# `booth config print` lists what a booth is configured with — the summary a save
# prints at its end — and writes nothing. Reconfigure flags apply, so it previews a
# change before making it.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
printed="$prj/printed.txt"

function check() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="${1}" message="${2}" width=64
    local label="${message} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad
    pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    local test="Test ${TEST_COUNT}: ${label}"
    echo -n "${test}${pad} "
    if [[ "${ok}" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test_label}: ${test}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

run booth config $prj --no-tui --select 'apt-pkg:htop/claude-code+auto-accept'
before="$(cd "$prj" && find .booth -type f -exec sha256sum {} + | sort)"

booth config print $prj > "$printed" 2>>"$log"
check $? "print succeeds on a configured booth"

grep -q '^  - Claude Code' "$printed" && grep -q '^    + Accept Edits$' "$printed"
check $? "it lists the templates and their extensions"

[[ "$(cd "$prj" && find .booth -type f -exec sha256sum {} + | sort)" == "$before" ]]
check $? "it writes nothing"

booth config print $prj --remove-select claude-code > "$printed" 2>>"$log"
! grep -q 'Claude Code' "$printed" && grep -q '^  - ' "$printed"
check $? "a reconfigure flag is previewed, not applied"

grep -q '^    + Accept Edits$' <(booth config print $prj 2>/dev/null)
check $? "the booth is unchanged after the preview"

! booth config print "$prj/nowhere" >/dev/null 2>&1
check $? "a folder with no booth is an error"

booth config --help | grep -q 'booth config print'
check $? "help mentions booth config print"

finally
