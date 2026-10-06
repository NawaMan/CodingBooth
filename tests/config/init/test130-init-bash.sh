#!/bin/bash
# bash: setup line, catalog default, a pin that is not the default,
# and +default pointing USER_SHELL at that release.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"
default_ver="$(template-default bash GNU_BASH_VERSION)"

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
        FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

run booth config $prj --no-tui --select 'bash'
assert-line "$boothfile" "setup bash" " --version \${GNU_BASH_VERSION}" "bash adds setup bash --version"
assert-line "$boothfile" "arg GNU_BASH_VERSION=" "$default_ver" \
    "bash default version is the catalog's"
check "bare bash leaves the login shell alone" \
    bash -c "! grep -q 'USER_SHELL=' '$prj/.booth/config.toml'"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'bash:5.2.37'
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg GNU_BASH_VERSION=" "5.2.37" "bash:5.2.37 pins GNU_BASH_VERSION"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'bash+default'
config="$prj/.booth/config.toml"
check "bash+default sets USER_SHELL to the default release" \
    grep -q "USER_SHELL=/opt/bash/bash-${default_ver}/bin/bash" "$config"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'bash:5.2.37+default'
config="$prj/.booth/config.toml"
check "bash:5.2.37+default follows the pin" \
    grep -q 'USER_SHELL=/opt/bash/bash-5.2.37/bin/bash' "$config"

finally
