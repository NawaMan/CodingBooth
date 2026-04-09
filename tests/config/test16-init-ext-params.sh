#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test extension params: maven version override
run booth config $prj --no-tui --select "java+maven:3.9"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg MAVEN_VERSION=" "3.9"            "MAVEN_VERSION overridden to 3.9"
assert-line "$boothfile" "setup mvn "        "\${MAVEN_VERSION}" "setup mvn uses MAVEN_VERSION"

# Test extension params: gradle version override
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "java+gradle:8.14"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg GRADLE_VERSION=" "8.14"             "GRADLE_VERSION overridden to 8.14"

# Test extension with default params (no override)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "java+maven"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg MAVEN_VERSION=" "3.9.12"            "MAVEN_VERSION uses default 3.9.12"

finally
