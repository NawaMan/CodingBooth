#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "homebrew/brew-pkg:tree"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg BREW_PKGS=" "tree"             "BREW_PKGS arg"
assert-line "$boothfile" "install brew " '${BREW_PKGS}'      "install brew line"
finally
