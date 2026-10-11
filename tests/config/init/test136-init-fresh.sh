#!/bin/bash
# fresh: setup line, catalog default, a pin that is not the default,
# and +config-shared's mount marker.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"
default_ver="$(template-default fresh FRESH_VERSION)"

default_theme="$(template-default fresh+theme FRESH_THEME)"

run booth config $prj --no-tui --select 'fresh'
assert-line "$boothfile" "setup fresh" " --version \${FRESH_VERSION}" "fresh adds setup fresh --version"
assert-line "$boothfile" "arg FRESH_VERSION=" "$default_ver" "fresh default version is the catalog's"
assert-line "$boothfile" "arg FRESH_THEME=" "$default_theme" "fresh+theme default theme is the catalog's"
startup="$prj/.booth/startups/74-fresh-theme--startup.sh"
TEST_COUNT=$((TEST_COUNT + 1))
label="fresh startup writes the catalog theme "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q "FRESH_THEME:-${default_theme}" "$startup"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: FRESH_THEME:-${default_theme} in $startup"
fi

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'fresh:0.5.2'
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg FRESH_VERSION=" "0.5.2" "fresh:0.5.2 pins FRESH_VERSION"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'fresh+theme:dracula'
boothfile="$prj/.booth/Boothfile"
startup="$prj/.booth/startups/74-fresh-theme--startup.sh"
assert-line "$boothfile" "arg FRESH_THEME=" "dracula" "fresh+theme:dracula pins FRESH_THEME"
TEST_COUNT=$((TEST_COUNT + 1))
label="pinned theme is the startup default "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q 'FRESH_THEME:-dracula' "$startup"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: FRESH_THEME:-dracula in $startup"
fi

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'fresh~theme'
TEST_COUNT=$((TEST_COUNT + 1))
label="fresh~theme writes no theme startup "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [[ ! -e "$prj/.booth/startups/74-fresh-theme--startup.sh" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: no $prj/.booth/startups/74-fresh-theme--startup.sh"
fi

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'fresh+config-shared'
TEST_COUNT=$((TEST_COUNT + 1))
label="config-shared creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/shared/home/coder/.config/fresh/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/shared/home/coder/.config/fresh/.mount-this"
fi

finally
