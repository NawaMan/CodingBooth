#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Posting with the default (pinned) version
run booth config $prj --no-tui --select "posting"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg POSTING_VERSION=' '2.11.0'                "default version is pinned to 2.11.0"
assert-line "$boothfile" 'setup posting ' '--version ${POSTING_VERSION}' "Boothfile uses the --version flag with param reference"

# Test 2: Posting pinned to another version
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "posting:latest"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg POSTING_VERSION=' 'latest'                "custom version param is latest"

finally
