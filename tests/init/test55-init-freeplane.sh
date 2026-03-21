#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Freeplane with default version
run booth init new $prj --select "freeplane"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg FREEPLANE_VERSION=' '1.12.8'  "default version is 1.12.8"
assert-line "$boothfile" 'setup freeplane ' '${FREEPLANE_VERSION}'  "Boothfile uses param reference"

# Test 2: Freeplane with custom version
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "freeplane:1.12.7"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg FREEPLANE_VERSION=' '1.12.7'  "custom version is 1.12.7"

finally
