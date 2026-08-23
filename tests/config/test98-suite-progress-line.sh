#!/bin/bash
# Guard: the transient status line the suite runners draw (tests/progress--source.sh).
#
# The two things that must never break are the two that are invisible when they
# do. It must draw nothing at all when there is no terminal — otherwise escape
# codes end up in a CI transcript or an expected-output fixture — and it must
# erase what it drew, or a run's scrollback fills with half-lines.
#
# The line itself goes to PROGRESS_TTY, which is /dev/tty in a real run and a file
# here, so the bytes that would have reached the terminal can be read back. There
# is no terminal inside a test, so PROGRESS_ACTIVE is forced where the drawing
# itself is under test; progress_init's own refusals are asserted separately.
source "$(dirname "$0")/test-helpers--source.sh"

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

root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done
helper="$root/tests/progress--source.sh"

[[ -f "$helper" ]]; assert-true "$?" "progress helper exists"

drawn="$(mktemp)"
trap 'rm -f "$drawn"' EXIT

# Set before sourcing, not as a `VAR=x source ...` prefix: bash restores the
# variable after the builtin returns, and the helper would keep /dev/tty.
PROGRESS_TTY="$drawn"
# shellcheck disable=SC1090
source "$helper"

ESC=$'\r\033[K'

# ── progress_init refuses, so a captured run stays byte-for-byte silent ──────
#
# Nothing in this suite has a terminal: the runner captures each test into
# out--<name>.log. That is the CI case, and the answer there is "draw nothing".
progress_init; init_rc=$?
[[ "$init_rc" -ne 0 && "$PROGRESS_ACTIVE" == "false" ]]
assert-true "$?" "progress_init refuses with no terminal on any stream"

before="$(wc -c <"$drawn")"
progress_draw "should not appear"
progress_clear
[[ "$(wc -c <"$drawn")" == "$before" ]]
assert-true "$?" "an inactive line writes nothing at all"

CB_NO_TEST_PROGRESS=1 progress_init
assert-true "$([[ $? -ne 0 ]] && echo 0 || echo 1)" "CB_NO_TEST_PROGRESS refuses the line"

# ── drawing ─────────────────────────────────────────────────────────────────
PROGRESS_ACTIVE=true
PROGRESS_START_DELAY=0
_PROGRESS_WIDTH=60

: >"$drawn"
out="$(progress_draw "4 in flight · test82 47s" 2>&1)"
[[ -z "$out" ]]
assert-true "$?" "drawing writes nothing to stdout or stderr"

line="$(cat "$drawn")"
[[ "$line" == "${ESC}"*"4 in flight · test82 47s" ]]
assert-true "$?" "the line is an in-place redraw of the given text"

[[ "$line" =~ ^$'\r'$'\033'\[K[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ]]
assert-true "$?" "the line carries a spinner frame"

: >"$drawn"
progress_draw "a"; progress_draw "b"
first="$(head -c 4 "$drawn" | cat -v)"
[[ "$(grep -c . <"$drawn")" -ge 1 && "$first" == '^M^[[K' ]]
assert-true "$?" "each redraw starts by clearing the same row"

# ── erasing ─────────────────────────────────────────────────────────────────
: >"$drawn"
progress_draw "something"
progress_clear
[[ "$(cat "$drawn")" == *"${ESC}" ]]
assert-true "$?" "progress_clear leaves the row empty"

: >"$drawn"
progress_clear
[[ ! -s "$drawn" ]]
assert-true "$?" "progress_clear with nothing drawn writes nothing"

# ── the start delay: a suite of fast tests must not flicker ─────────────────
: >"$drawn"
PROGRESS_START_DELAY=9999
_PROGRESS_QUIET_SINCE=$SECONDS
progress_draw "too early to matter"
[[ ! -s "$drawn" ]]
assert-true "$?" "nothing is drawn during the start delay"
PROGRESS_START_DELAY=0

# ── width: a wrapped line leaves a stray row behind ─────────────────────────
: >"$drawn"
_PROGRESS_WIDTH=40
progress_draw "$(printf 'x%.0s' $(seq 1 200))"
body="$(cat "$drawn")"; body="${body#"$ESC"}"
[[ ${#body} -le 39 && "$body" == *"…" ]]
assert-true "$?" "an over-long line is truncated to fit the width"

# ── the clock ───────────────────────────────────────────────────────────────
[[ "$(progress_elapsed 100 145)" == "45s" ]]
assert-true "$?" "progress_elapsed renders seconds"

[[ "$(progress_elapsed 0 449)" == "7m29s" ]]
assert-true "$?" "progress_elapsed renders minutes and seconds"

[[ "$(progress_elapsed 0 4020)" == "1h07m" ]]
assert-true "$?" "progress_elapsed renders hours and minutes"

[[ "$(progress_elapsed 500 100)" == "0s" ]]
assert-true "$?" "a clock that would run backwards reads 0s"

progress_elapsed_var el 0 449
[[ "$el" == "7m29s" ]]
assert-true "$?" "progress_elapsed_var matches progress_elapsed"

# ── the detail: the last thing the run actually said ────────────────────────
log_probe="$(mktemp)"
printf 'first\nsecond\n\n   \n' >"$log_probe"
[[ "$(progress_tail "$log_probe")" == "second" ]]
assert-true "$?" "progress_tail skips trailing blank lines"

# A curl meter is one \r-rewritten line: the newest state is what matters, and
# deleting the carriage returns would report the oldest instead.
printf 'start\n 1%% done\r 55%% done\r 99%% done\n' >"$log_probe"
[[ "$(progress_tail "$log_probe")" == "99% done" ]]
assert-true "$?" "progress_tail reports the newest state of a rewritten line"

printf '\033[32mgreen\033[0m text\n' >"$log_probe"
[[ "$(progress_tail "$log_probe")" == "green text" ]]
assert-true "$?" "progress_tail strips colour codes"

[[ "$(progress_tail "$log_probe" 5)" == "green" ]]
assert-true "$?" "progress_tail honours the length limit"

[[ -z "$(progress_tail "${log_probe}-does-not-exist")" ]]
assert-true "$?" "progress_tail on a missing log is empty"

# Bounded: a runaway log must not be read into a variable whole. 8MB of a single
# line, and the read stays inside the 4KB window.
{ printf 'runaway '; head -c 8000000 /dev/zero | tr '\0' 'y'; printf '\n'; } >"$log_probe"
result="$(progress_tail "$log_probe")"
[[ ${#result} -le 100 ]]
assert-true "$?" "progress_tail stays bounded on a runaway log"

rm -f "$log_probe"

finally
