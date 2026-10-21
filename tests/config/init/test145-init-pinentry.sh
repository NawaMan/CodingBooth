#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# Test 1: pinentry with the default flavor — the catalog's, wired into the setup line
run booth config $prj --no-tui --select "pinentry"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PINENTRY_FLAVOR=' "$(template-default pinentry PINENTRY_FLAVOR)"  "default flavor is the catalog's"
assert-line "$boothfile" 'setup pinentry ' '--flavor ${PINENTRY_FLAVOR}'  "Boothfile uses param reference"

# Test 2: a pinned flavor
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "pinentry:qt"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PINENTRY_FLAVOR=' 'qt'  "flavor pin is qt"

finally
