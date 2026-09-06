#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "mongodb+start"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "setup mongodb --version " '${MONGO_VERSION}' "mongodb setup"
assert-line "$boothfile" "setup mongodb-start" ""                     "start extension forks mongod on boot"
finally
