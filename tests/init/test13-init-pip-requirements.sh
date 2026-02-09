#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "python+pip"

# Create requirements.txt in .booth/
echo "requests" > "$prj/.booth/requirements.txt"

booth-collect "
echo -n '1: ' ; python3 -c 'import requests; print(\"OK\")' 2>&1 ;
"

assert-line "$tmpfile" "1: " "OK"  "requests is installed via pip"
finally
