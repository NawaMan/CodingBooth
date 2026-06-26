#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "apt-pkg:htop,jq"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg APT_PKGS=" "htop,jq"          "APT_PKGS arg"
assert-line "$boothfile" "install apt " '${APT_PKGS}'      "install apt line"
finally
