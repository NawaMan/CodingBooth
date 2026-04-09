#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "nodejs+npm-pkg:cowsay"

booth-collect "
echo -n '1: ' ; which cowsay 2>&1 ;
"

assert-line "$tmpfile" "1: " "/usr/local/bin/cowsay"  "cowsay is installed via npm"
finally
