#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

# gleam is only a compiler; gleam run / gleam test need Erlang/OTP. The template
# requires erlang, so a bare `gleam` select must pull in setup erlang (with its
# OTP pin) ahead of setup gleam, and the version pin must land on the arg.

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

line_of() { grep -n "^$1" "$boothfile" | head -1 | cut -d: -f1; }
erlang_before_gleam() {
    local e g
    e="$(line_of 'setup erlang ')"; g="$(line_of 'setup gleam ')"
    [[ -n "$e" && -n "$g" && "$e" -lt "$g" ]]
}

# --- bare gleam: default version, erlang comes along -----------------------
run booth config $prj --no-tui --select 'gleam'
assert-line "$boothfile" "setup gleam" " --version \${GLEAM_VERSION}" "gleam adds setup gleam --version"
assert-line "$boothfile" "arg GLEAM_VERSION=" "latest"                 "GLEAM_VERSION defaults to latest"
assert-line "$boothfile" "setup erlang" " --otp-version \${OTP_VERSION}" "gleam pulls in the erlang template"
check "setup erlang runs before setup gleam" erlang_before_gleam

# --- pinned ----------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'gleam:1.17.0'
assert-line "$boothfile" "arg GLEAM_VERSION=" "1.17.0" "gleam:1.17.0 pins GLEAM_VERSION"

# --- VS Code extension is auto-selected (its script skips itself without code-server)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant codeserver --select 'gleam'
assert-line "$boothfile" "setup gleam-code-extension" "" "gleam auto-selects its VS Code extension"

finally
