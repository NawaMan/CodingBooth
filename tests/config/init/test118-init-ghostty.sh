#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

# ghostty auto-selects +fancy (the styled config), which must run after
# `setup ghostty`, and can be dropped with `~` for the plain default config.

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
fancy_after_ghostty() {
    local g f
    g="$(line_of 'setup ghostty')"; f="$(line_of 'setup ghostty-fancy')"
    [[ -n "$g" && -n "$f" && "$f" -gt "$g" ]]
}
no_fancy() { ! grep -q "^setup ghostty-fancy" "$boothfile"; }

# --- plain ghostty: +fancy comes along ---------------------------------------
run booth config $prj --no-tui --variant xfce --select 'ghostty'
assert-line "$boothfile" "setup ghostty" "" "ghostty adds setup ghostty"
assert-line "$boothfile" "setup ghostty-fancy" "" "ghostty auto-selects +fancy"
check "setup ghostty-fancy runs after setup ghostty" fancy_after_ghostty

# --- ghostty~fancy: plain config -----------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select 'ghostty~fancy'
assert-line "$boothfile" "setup ghostty" "" "ghostty~fancy still sets up ghostty"
check "ghostty~fancy drops setup ghostty-fancy" no_fancy

finally
