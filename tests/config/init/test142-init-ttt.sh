#!/bin/bash
# ttt: setup line, version pin, config-shared mount
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

# --- bare ttt: latest --------------------------------------------------------
run booth config $prj --no-tui --select 'ttt'
assert-line "$boothfile" "setup ttt" " --version \${TTT_VERSION}" "ttt adds setup ttt --version"
assert-line "$boothfile" "arg TTT_VERSION=" "$(template-default ttt TTT_VERSION)" "TTT_VERSION default is the catalog's"

# --- pinned ------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'ttt:1.8.0'
assert-line "$boothfile" "arg TTT_VERSION=" "1.8.0" "ttt:1.8.0 pins TTT_VERSION"

# --- config-shared creates the shared mount marker ---------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'ttt+config-shared'
TEST_COUNT=$((TEST_COUNT + 1))
label="config-shared creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/shared/home/coder/.config/ttt/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/shared/home/coder/.config/ttt/.mount-this"
fi

finally
