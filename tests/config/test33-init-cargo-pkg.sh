#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "rust+cargo-pkg:bat"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg CARGO_PKGS=" "bat"             "CARGO_PKGS arg"
assert-line "$boothfile" "install cargo " '${CARGO_PKGS}'    "install cargo line"
finally
