#!/bin/bash
# Template test: Jupyter Notebook (needs Python)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "python/notebook"

booth-collect "
echo -n '1: ' ; command -v jupyter >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Jupyter Notebook is installed"
finally
