#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# Test 1: Freeplane with default version
run booth config $prj --no-tui --select "freeplane"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg FREEPLANE_VERSION=' "$(template-default freeplane FREEPLANE_VERSION)"  "default version is the catalog's"
assert-line "$boothfile" 'setup freeplane ' '${FREEPLANE_VERSION}'  "Boothfile uses param reference"

# Test 2: Freeplane with custom version
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "freeplane:1.12.7"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg FREEPLANE_VERSION=' '1.12.7'  "custom version is 1.12.7"

finally
