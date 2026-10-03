#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

# eclipse--setup.sh exits 1 when `java` is missing, and no variant ships a JDK,
# so a bare `eclipse` select used to generate a Boothfile whose build failed at
# `RUN eclipse--setup.sh` ("'java' command not found"). The template now
# requires java: selecting eclipse alone must pull the JDK in, ahead of it.

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
jdk_before_eclipse() {
    local j e
    j="$(line_of 'setup jdk ')"; e="$(line_of 'setup eclipse$')"
    [[ -n "$j" && -n "$e" && "$j" -lt "$e" ]]
}

# --- bare eclipse: java comes along --------------------------------------
run booth config $prj --no-tui --variant xfce --select 'eclipse'
assert-line "$boothfile" "setup eclipse" "" "eclipse adds setup eclipse"
assert-line "$boothfile" "setup jdk" " \${JDK_VERSION} \${JDK_VENDOR}" "eclipse pulls in the java template's setup jdk"
check "setup jdk runs before setup eclipse" jdk_before_eclipse

finally
