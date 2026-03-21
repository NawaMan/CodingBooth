#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Obsidian with default version
run booth init new $prj --select "obsidian"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg OBSIDIAN_VERSION=' '1.12.4'  "default version is 1.12.4"
assert-line "$boothfile" 'setup obsidian ' '${OBSIDIAN_VERSION}'  "Boothfile uses param reference"

# Test 2: Obsidian with custom version
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "obsidian:1.12.3"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg OBSIDIAN_VERSION=' '1.12.3'  "custom version is 1.12.3"

finally
