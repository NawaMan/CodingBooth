#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: AFFiNE Desktop with default version
run booth config $prj --no-tui --select "affine-desktop"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg AFFINE_DESKTOP_VERSION=' '0.27.4'  "default version is 0.27.4"
assert-line "$boothfile" 'setup affine-desktop ' '${AFFINE_DESKTOP_VERSION}'  "Boothfile uses param reference"

# Test 2: AFFiNE Desktop with custom version
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-desktop:0.27.3"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg AFFINE_DESKTOP_VERSION=' '0.27.3'  "custom version is 0.27.3"

finally
