#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "go+go-pkg:gopls@latest"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg GO_PKGS=" "gopls@latest"  "GO_PKGS arg"
assert-line "$boothfile" 'install go ${GO_PKGS}' ""                            "install go line"
finally
