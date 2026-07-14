#!/bin/bash
# `booth config --no-tui` must treat the existing .booth/ as its baseline, the way
# the TUI does.
#
# It used to read only config.toml's long-form run-args, never the "# Configured by:"
# header — so it rebuilt from an empty selection whenever --select was not restated.
# The Boothfile escaped by luck (an empty one serializes to "", and the writer skips
# empty content), but config.toml has content regardless and WAS rewritten: variant,
# port, cmds and every template-contributed run-arg were dropped, while the envs and
# mounts survived because those are recovered from config.toml itself. Losing the
# variant silently rebuilds the booth on the wrong base image.
#
# The header is now parsed back as the baseline, and this invocation's flags override
# it. That makes the flags that steer the run (--overwrite, --beside, ...) the one
# thing that must NOT be inherited: the header itself reads "booth config --no-tui
# --overwrite ...", so inheriting them would make every later run an overwriting one
# and quietly disarm the guard.
source "$(dirname "$0")/test-helpers--source.sh"

begin
boothfile="$prj/.booth/Boothfile"
configtoml="$prj/.booth/config.toml"

# has <file> <substring> — 0 when the file contains it
function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }

# check <0-if-ok> <message>
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

# ---------------------------------------------------------------------------
# 1) Seed a booth: a selection, a pinned param, a variant and an env.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "go:1.25.4/python" --variant codeserver --env "FOO=1"
assert-line "$boothfile"  "arg GO_VERSION=" "1.25.4"      "seeded: go is pinned to 1.25.4"
assert-line "$configtoml" "variant = "      '"codeserver"' "seeded: variant is codeserver"

# ---------------------------------------------------------------------------
# 2) The bug: reconfigure WITHOUT restating --select. The selection must survive.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite
assert-line "$boothfile"  "arg GO_VERSION=" "1.25.4"      "selection survives a reconfigure that omits --select"
assert-line "$configtoml" "variant = "      '"codeserver"' "variant survives it too"
has "$boothfile" 'setup python' ; check $? "the rest of the selection survives (python)"
has "$boothfile" '--select go:1.25.4/python' ; check $? "the header still records the selection"
has "$configtoml" '"--env", "FOO=1"' ; check $? "the env survives (it always did — via config.toml)"

# ---------------------------------------------------------------------------
# 3) Flags from this invocation override the baseline, they do not merge into it.
#    Restating --env replaces the saved list, which is what makes an env removable.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --env "BAR=2"
has  "$configtoml" '"--env", "BAR=2"' ; check $? "a restated --env is applied"
!(has "$configtoml" '"--env", "FOO=1"') ; check $? "...and replaces the saved list rather than unioning"
assert-line "$boothfile" "arg GO_VERSION=" "1.25.4"      "the selection is still untouched by an --env-only run"

# ---------------------------------------------------------------------------
# 4) The header says "--no-tui --overwrite". That must NOT be inherited, or every
#    later run would overwrite silently. Without --overwrite, an existing booth
#    still has to ask — and with no stdin to answer, it aborts rather than writes.
# ---------------------------------------------------------------------------
out="$(booth config $prj --no-tui --select go < /dev/null 2>&1)"; code=$?
{ echo ""; echo "> booth config (no --overwrite, existing booth)"; echo "$out"; echo "(exit ${code})"; } >> $log
[[ $code -ne 0 ]] ; check $? "--overwrite is not inherited from the header"
grep -q "Overwrite?" <<< "$out" ; check $? "...the existing-files prompt is still raised"
assert-line "$boothfile" "arg GO_VERSION=" "1.25.4"      "the aborted run left the booth intact"

finally
