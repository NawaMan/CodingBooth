#!/bin/bash
# `booth config repair` makes files edited outside booth config count as
# generated again — when the edits read back. A readable edit is recorded in the
# header and only the guarded files and the fingerprint change: a hand-edited
# home-seed file is not re-copied. An edit it cannot read back is refused, with
# nothing written. It attempts; it never forces. `booth config validate` is the
# same reading, check-only: exit 0 when generated, 1 when not, nothing written.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
booth_dir="$prj/.booth"
before="$prj/before"

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
function changed-files() {
    (cd "$prj" && diff -rq before .booth 2>&1 | sed -E 's#^Files before/(.*) and .*#\1#; s#^Only in ([^:]*): (.*)#\1/\2#' | LC_ALL=C sort | tr '\n' ' ')
}
function snapshot() { rm -rf "$before" && cp -a "$booth_dir" "$before"; }

run booth config $prj --no-tui --select 'apt-pkg:htop/claude-code+auto-accept'
seed="$booth_dir/home-seed/.claude/settings.json"
echo '// my deny rules' >> "$seed"

run booth config repair $prj
check $? "a generated booth has nothing to repair"

run booth config validate $prj
check $? "validate: a generated booth is valid"

echo 'timezone = "Asia/Bangkok"' >> "$booth_dir/config.toml"
snapshot
! run booth config validate $prj && [[ -z "$(changed-files)" ]]
check $? "validate: a hand edit is not valid, and nothing is written"

run booth config repair $prj --dryrun
[[ $? -eq 0 && -z "$(changed-files)" ]]
check $? "--dryrun writes nothing"

run booth config repair $prj
check $? "a readable edit is repaired"

[[ "$(changed-files)" == ".generated Boothfile config.toml " ]]
check $? "only the guarded files and the fingerprint change"

grep -q '^# Configured by:.*--set timezone=Asia/Bangkok' "$booth_dir/config.toml" \
    && grep -q '^timezone = "Asia/Bangkok"$' "$booth_dir/config.toml"
check $? "the edit is kept and recorded in the header"

grep -q '^// my deny rules$' "$seed"
check $? "a hand-edited home-seed file is not re-copied"

run booth config $prj --no-tui --dryrun
check $? "the booth is generated again (no drift refusal)"

run booth config validate $prj
check $? "validate: the repaired booth is valid"

echo 'run echo mine' >> "$booth_dir/Boothfile"
snapshot
! run booth config repair $prj
check $? "an edit that cannot be read back is refused"

[[ -z "$(changed-files)" ]]
check $? "and nothing is written"

! run booth config validate $prj
check $? "validate: an unrepairable edit is not valid"

finally
