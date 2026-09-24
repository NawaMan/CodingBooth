#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

# The xfce template auto-selects +modern-theme (Greybird-dark/Adwaita) and
# +plank (Plank Reloaded dock), so a Boothfile-built XFCE booth gets the same
# look as the desktop-xfce variant. Both must run after `setup xfce` (they skip
# when XFCE is absent), and each can be dropped with `~`.

begin

boothfile="$prj/.booth/Boothfile"

# pass/fail line in the same format as assert-line, for checks it can't express
check() {
    local label="$1"; shift
    TEST_COUNT=$((TEST_COUNT + 1))
    local pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

line_of() { grep -n -x "$1" "$boothfile" | head -1 | cut -d: -f1; }
after_xfce() {
    local x t
    x="$(line_of 'setup xfce')"; t="$(line_of "$1")"
    [[ -n "$x" && -n "$t" && "$t" -gt "$x" ]]
}
absent() { ! grep -q "^$1" "$boothfile"; }

# --- plain xfce: both extensions come along --------------------------------
run booth config $prj --no-tui --select 'xfce'
assert-line "$boothfile" "setup xfce-theme" ""                   "xfce auto-selects +modern-theme"
assert-line "$boothfile" "setup plank" ' ${PLANK_VERSION}'       "xfce auto-selects +plank"
assert-line "$boothfile" "arg PLANK_VERSION=" ""                 "PLANK_VERSION defaults to empty (latest)"
check "setup xfce-theme runs after setup xfce" after_xfce 'setup xfce-theme'
check "setup plank runs after setup xfce"      after_xfce 'setup plank ${PLANK_VERSION}'

# --- naming an auto-selected extension with a param pins it ----------------
run booth config $prj --no-tui --overwrite --select 'xfce+plank:0.11.172-1'
assert-line "$boothfile" "arg PLANK_VERSION=" "0.11.172-1"       "xfce+plank:<ver> pins PLANK_VERSION"
run booth config $prj --no-tui --overwrite
assert-line "$boothfile" "arg PLANK_VERSION=" "0.11.172-1"       "the pin survives a reconfigure"

# --- each can be excluded ---------------------------------------------------
run booth config $prj --no-tui --overwrite --select 'xfce~plank'
check "xfce~plank drops setup plank"            absent 'setup plank'
assert-line "$boothfile" "setup xfce-theme" ""                   "xfce~plank keeps +modern-theme"

run booth config $prj --no-tui --overwrite --select 'xfce~modern-theme'
check "xfce~modern-theme drops setup xfce-theme" absent 'setup xfce-theme'
assert-line "$boothfile" "setup plank" ' ${PLANK_VERSION}'       "xfce~modern-theme keeps +plank"

finally
