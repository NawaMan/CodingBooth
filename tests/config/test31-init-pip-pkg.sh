#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "python+pip-pkg:cowsay"

booth-collect "
echo -n '1: ' ; python3 -c 'import cowsay; print(\"OK\")' 2>&1 ;
"

assert-line "$tmpfile" "1: " "OK"  "cowsay is installed via pip"
finally
