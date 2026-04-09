#!/bin/bash
# Template test: Lua (standalone)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "lua"

booth-collect "
echo -n '1: ' ; command -v lua >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Lua is installed"
finally
