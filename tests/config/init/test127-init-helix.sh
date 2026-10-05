#!/bin/bash
# helix: setup line, version pin, config-shared mount
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

# --- bare helix: latest ------------------------------------------------------
run booth config $prj --no-tui --select 'helix'
assert-line "$boothfile" "setup helix" " --version \${HELIX_VERSION}" "helix adds setup helix --version"
assert-line "$boothfile" "arg HELIX_VERSION=" "latest" "HELIX_VERSION defaults to latest"

# --- pinned ------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'helix:25.07.1'
assert-line "$boothfile" "arg HELIX_VERSION=" "25.07.1" "helix:25.07.1 pins HELIX_VERSION"

# --- config-shared creates the shared mount marker ---------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'helix+config-shared'
TEST_COUNT=$((TEST_COUNT + 1))
label="config-shared creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/shared/home/coder/.config/helix/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/shared/home/coder/.config/helix/.mount-this"
fi

finally
