#!/bin/bash
# Template test: Python + pip extension
# Tests that the pip extension generates a Boothfile--90 segment and that
# pip install runs (with a requirements.txt containing a small package).
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "python+pip"

# Create a minimal requirements.txt so pip has something to install
mkdir -p "$prj/.booth"
echo "cowsay" > "$prj/.booth/requirements.txt"

booth-collect "
echo -n '1: ' ; command -v python3 >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v pip     >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; command -v cowsay  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Python is installed"
assert-line "$tmpfile" "2: " "OK"  "pip is installed"
assert-line "$tmpfile" "3: " "OK"  "cowsay installed via pip requirements.txt"
finally
