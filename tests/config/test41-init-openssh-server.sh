#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "openssh+server"

boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"

assert-line "$boothfile" "setup openssh" ""                   "setup openssh client line"
assert-line "$boothfile" "setup opensshd " '${SSH_PORT}'      "setup opensshd line"
assert-line "$boothfile" "arg SSH_PORT=" "2222"               "SSH_PORT default arg"
assert-line "$boothfile" "expose " '${SSH_PORT}'              "expose SSH_PORT line"
finally
