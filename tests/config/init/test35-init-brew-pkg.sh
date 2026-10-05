#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "homebrew/brew-pkg:tree"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg BREW_PKGS=" "tree"             "BREW_PKGS arg"
assert-line "$boothfile" "install brew " '${BREW_PKGS}'      "install brew line"
# `booth exec` does not read shell startup files. The image PATH is what makes
# a brew formula resolvable there. $PATH must stay literal for Docker to expand.
assert-line "$boothfile" "env PATH=" '/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH' "linuxbrew on image PATH"
finally
