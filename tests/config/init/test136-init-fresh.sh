#!/bin/bash
# fresh: setup line, catalog default, a pin that is not the default,
# and +config-shared's mount marker.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"
default_ver="$(template-default fresh FRESH_VERSION)"

run booth config $prj --no-tui --select 'fresh'
assert-line "$boothfile" "setup fresh" " --version \${FRESH_VERSION}" "fresh adds setup fresh --version"
assert-line "$boothfile" "arg FRESH_VERSION=" "$default_ver" "fresh default version is the catalog's"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'fresh:0.5.2'
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg FRESH_VERSION=" "0.5.2" "fresh:0.5.2 pins FRESH_VERSION"

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
