#!/bin/bash
# `booth config --no-tui --apt-snapshot <id>` with nothing else to change edits one
# line: the Boothfile's `env APT_SNAPSHOT=`. Every other file in .booth/ is left
# as it is — a hand-edited home-seed file, startup or config.toml included — so it
# needs no --overwrite, and moving the date can no longer drop the user's deny
# rules (the 0.82.0 rollout's GeekPresent case). A generated Boothfile stays
# generated: .booth/.generated is re-stamped, so the next reconfigure does not
# call it hand-written. A hand-written one gets the line changed and stays
# hand-written. Any other flag alongside it is a full reconfigure, as before.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
booth_dir="$prj/.booth"
boothfile="$booth_dir/Boothfile"
before="$prj/before"

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
        FAIL_TESTS+=("${test_label}: ${test}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}
# changed-files: the files under .booth/ that differ from the snapshot in $before.
function changed-files() {
    (cd "$prj" && diff -rq before .booth 2>&1 | sed -E 's#^Files before/(.*) and .*#\1#; s#^Only in ([^:]*): (.*)#\1/\2#' | LC_ALL=C sort | tr '\n' ' ')
}

unset CB_APT_SNAPSHOT

run booth config $prj --no-tui --select 'apt-pkg:htop/claude-code+auto-accept'

# Hand edits a full reconfigure would replace (or refuse over).
seed="$booth_dir/home-seed/.claude/settings.json"
startup="$(ls "$booth_dir"/startups/*--startup.sh | head -1)"
echo '// my deny rules' >> "$seed"
echo '# my tweak'       >> "$startup"
rm -rf "$before" && cp -a "$booth_dir" "$before"

run booth config $prj --no-tui --apt-snapshot 20250101T000000Z </dev/null
check $? "--apt-snapshot alone succeeds without --overwrite"

[[ "$(snapshot-line)" == "env APT_SNAPSHOT=20250101T000000Z" ]]
check $? "the snapshot line is moved"

[[ "$(changed-files)" == ".generated Boothfile " ]]
check $? "only the Boothfile and its fingerprint change"

[[ "$(diff "$before/Boothfile" "$boothfile" | grep -c '^[<>]')" == "2" ]]
check $? "the Boothfile differs by that one line"

run booth config $prj --no-tui --dryrun
check $? "the Boothfile is still booth config's own (no drift refusal)"

rm -rf "$before" && cp -a "$booth_dir" "$before"
run booth config $prj --no-tui --dryrun --apt-snapshot 20261023T000000Z
[[ $? -eq 0 && -z "$(changed-files)" ]]
check $? "--dryrun --apt-snapshot writes nothing"

run booth config $prj --no-tui --overwrite --apt-snapshot 20250101T000000Z
[[ $? -eq 0 && -z "$(changed-files)" ]]
check $? "the same snapshot again writes nothing"

# A Boothfile the user wrote: the line still moves, and it stays theirs.
sed -i.orig '/^# Configured by:/d' "$boothfile" && rm -f "$boothfile.orig"
echo 'run echo mine' >> "$boothfile"
rm -rf "$before" && cp -a "$booth_dir" "$before"
run booth config $prj --no-tui --apt-snapshot none </dev/null
check $? "a hand-written Boothfile is not refused"

[[ "$(snapshot-line)" == "env APT_SNAPSHOT=" ]] && grep -q '^run echo mine$' "$boothfile"
check $? "its line is set and the user's lines are kept"

[[ "$(changed-files)" == "Boothfile " ]]
check $? "its fingerprint is not re-stamped as generated"

! run booth config $prj --no-tui --dryrun
check $? "it is still treated as hand-written afterwards"

finally
