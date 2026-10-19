#!/bin/bash
# differ: setup line, catalog default, and a pin that is not the default.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"
default_ver="$(template-default differ DIFFER_VERSION)"

run booth config $prj --no-tui --select 'differ'
assert-line "$boothfile" "setup differ" " --version \${DIFFER_VERSION}" "differ adds setup differ --version"
assert-line "$boothfile" "arg DIFFER_VERSION=" "$default_ver" "differ default version is the catalog's"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'differ:1.8.0'
assert-line "$boothfile" "arg DIFFER_VERSION=" "1.8.0" "differ:1.8.0 pins DIFFER_VERSION"

finally
