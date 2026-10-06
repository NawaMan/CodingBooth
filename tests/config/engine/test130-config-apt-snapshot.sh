#!/bin/bash
# The `env APT_SNAPSHOT=` freeze over a booth's life: the first configure stamps
# today, a plain reconfigure keeps whatever is there, and --apt-snapshot is the
# only way to move it — an id, `today`, or `none`. `none` is an empty line, not a
# missing one, so the reconfigure after it keeps the freeze off instead of
# stamping today again. The header never records the flag: it is replayed on
# every reconfigure, and a recorded `today` would move the freeze each time.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
boothfile="$prj/.booth/Boothfile"
today="$(date -u +%Y%m%d)T000000Z"

function snapshot-line() { grep '^env APT_SNAPSHOT=' "$boothfile" 2>/dev/null ; }
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
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

# CB_APT_SNAPSHOT would override the existing line and hide the behaviour under test.
unset CB_APT_SNAPSHOT

run booth config $prj --no-tui --select apt-pkg:htop
[[ "$(snapshot-line)" == "env APT_SNAPSHOT=${today}" ]]
check $? "the first configure stamps today"

run booth config $prj --no-tui --overwrite --apt-snapshot 20250101T000000Z
[[ "$(snapshot-line)" == "env APT_SNAPSHOT=20250101T000000Z" ]]
check $? "--apt-snapshot <id> sets that snapshot"

run booth config $prj --no-tui --overwrite --add-env FOO=1
[[ "$(snapshot-line)" == "env APT_SNAPSHOT=20250101T000000Z" ]]
check $? "a plain reconfigure keeps the existing snapshot"

! grep -q -- "--apt-snapshot" "$boothfile"
check $? "the header never records --apt-snapshot"

run booth config $prj --no-tui --overwrite --apt-snapshot none
[[ "$(snapshot-line)" == "env APT_SNAPSHOT=" ]]
check $? "--apt-snapshot none writes an empty line"

run booth config $prj --no-tui --overwrite
[[ "$(snapshot-line)" == "env APT_SNAPSHOT=" ]]
check $? "the reconfigure after none keeps the freeze off"

run booth config $prj --no-tui --overwrite --apt-snapshot today
[[ "$(snapshot-line)" == "env APT_SNAPSHOT=${today}" ]]
check $? "--apt-snapshot today moves it to today"

cp "$boothfile" "$prj/Boothfile.before"
run booth config $prj --no-tui --overwrite --apt-snapshot 2026-01-01
status=$?
[[ $status -ne 0 ]] && cmp -s "$boothfile" "$prj/Boothfile.before"
check $? "a malformed id is refused and nothing is written"

finally
