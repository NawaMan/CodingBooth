#!/bin/bash
# Template test: Homebrew (standalone, slow — clones from GitHub)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "homebrew"

booth-collect "
echo -n '1: ' ; command -v brew >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Homebrew is installed"
finally
