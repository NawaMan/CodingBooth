#!/bin/bash
# superfile: setup line, catalog default, and a pin that is not the default.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"
default_ver="$(template-default superfile SUPERFILE_VERSION)"

run booth config $prj --no-tui --select 'superfile'
assert-line "$boothfile" "setup superfile" " --version \${SUPERFILE_VERSION}" "superfile adds setup superfile --version"
assert-line "$boothfile" "arg SUPERFILE_VERSION=" "$default_ver" "superfile default version is the catalog's"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'superfile:1.6.0'
assert-line "$boothfile" "arg SUPERFILE_VERSION=" "1.6.0" "superfile:1.6.0 pins SUPERFILE_VERSION"

finally
