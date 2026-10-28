#!/bin/bash
# Zed editor template: default version from the catalog, a pin lands, setup line wiring.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# --- default ---
run booth config $prj --no-tui --variant xfce --select "zed"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg ZED_VERSION=" "$(template-default zed ZED_VERSION)"  "zed default version is the catalog's"
assert-line "$boothfile" "setup zed --version " '${ZED_VERSION}'  "zed setup line"

# --- version pin ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "zed:1.24.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg ZED_VERSION=" '1.24.0'  "zed version pin"

finally
