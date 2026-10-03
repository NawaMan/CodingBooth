#!/bin/bash
# xonsh: setup line, version pin, python comes along, +default sets USER_SHELL
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

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

line_of() { grep -n "^$1" "$boothfile" | head -1 | cut -d: -f1; }
python_before_xonsh() {
    local p x
    p="$(line_of 'setup python ')"; x="$(line_of 'setup xonsh ')"
    [[ -n "$p" && -n "$x" && "$p" -lt "$x" ]]
}

# --- bare xonsh: latest, python comes along ----------------------------------
run booth config $prj --no-tui --select 'xonsh'
assert-line "$boothfile" "setup xonsh" " --version \${XONSH_VERSION}" "xonsh adds setup xonsh --version"
assert-line "$boothfile" "arg XONSH_VERSION=" "latest" "XONSH_VERSION defaults to latest"
assert-line "$boothfile" "setup python" " \${PYTHON_VERSION}" "xonsh pulls in the python template"
check "setup python runs before setup xonsh" python_before_xonsh

# --- pinned ------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'xonsh:0.24.2'
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg XONSH_VERSION=" "0.24.2" "xonsh:0.24.2 pins XONSH_VERSION"

# --- +default sets the login shell -------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'xonsh+default'
config="$prj/.booth/config.toml"
check "xonsh+default sets USER_SHELL" grep -q 'USER_SHELL=/usr/local/bin/xonsh' "$config"

finally
