#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "tty-owner"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "setup " "tty-owner" "setup tty-owner line"
finally
