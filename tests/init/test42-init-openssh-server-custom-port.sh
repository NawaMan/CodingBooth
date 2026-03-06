#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "openssh+server:2200"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg SSH_PORT=" "2200"               "SSH_PORT custom arg"
assert-line "$boothfile" "setup opensshd " '${SSH_PORT}'      "setup opensshd line"
finally
