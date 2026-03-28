#!/bin/bash
# Template test: Ruby + PHP (scripting languages)
# Note: Lua excluded — lua--setup.sh has a readline linker bug (pre-existing).
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "ruby/php"

booth-collect "
echo -n '1: ' ; command -v ruby >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v php  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Ruby is installed"
assert-line "$tmpfile" "2: " "OK"  "PHP is installed"
finally
