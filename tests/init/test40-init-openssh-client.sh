#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "openssh"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "setup openssh" ""  "setup openssh line"
finally
