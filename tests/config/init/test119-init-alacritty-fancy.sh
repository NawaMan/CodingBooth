#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

# alacritty auto-selects +fancy (the styled config), which must run after
# `setup alacritty`, and can be dropped with `~` for the plain default config.

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
fancy_after_alacritty() {
    local g f
    g="$(line_of 'setup alacritty')"; f="$(line_of 'setup alacritty-fancy')"
    [[ -n "$g" && -n "$f" && "$f" -gt "$g" ]]
}
no_fancy() { ! grep -q "^setup alacritty-fancy" "$boothfile"; }

# --- plain alacritty: +fancy comes along -------------------------------------
run booth config $prj --no-tui --variant xfce --select 'alacritty'
assert-line "$boothfile" "setup alacritty" "" "alacritty adds setup alacritty"
assert-line "$boothfile" "setup alacritty-fancy" "" "alacritty auto-selects +fancy"
check "setup alacritty-fancy runs after setup alacritty" fancy_after_alacritty

# --- alacritty~fancy: plain config -----------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select 'alacritty~fancy'
assert-line "$boothfile" "setup alacritty" "" "alacritty~fancy still sets up alacritty"
check "alacritty~fancy drops setup alacritty-fancy" no_fancy

finally
