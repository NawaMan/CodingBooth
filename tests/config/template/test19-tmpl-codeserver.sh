#!/bin/bash
# Template test: code-server (web-based VS Code)
# Needs Python for Jupyter integration.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "python/codeserver"

booth-collect "
echo -n '1: ' ; command -v code-server >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "code-server is installed"
finally
