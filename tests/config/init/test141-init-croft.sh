#!/bin/bash
# croft: setup line, version pin, config-shared mount
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

# --- bare croft: latest ------------------------------------------------------
run booth config $prj --no-tui --select 'croft'
assert-line "$boothfile" "setup croft" " --version \${CROFT_VERSION}" "croft adds setup croft --version"
assert-line "$boothfile" "arg CROFT_VERSION=" "$(template-default croft CROFT_VERSION)" "CROFT_VERSION default is the catalog's"

# --- pinned ------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'croft:0.2.32'
assert-line "$boothfile" "arg CROFT_VERSION=" "0.2.32" "croft:0.2.32 pins CROFT_VERSION"

# --- config-shared creates the shared mount marker ---------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'croft+config-shared'
TEST_COUNT=$((TEST_COUNT + 1))
label="config-shared creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/shared/home/coder/.config/croft/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/shared/home/coder/.config/croft/.mount-this"
fi

finally
