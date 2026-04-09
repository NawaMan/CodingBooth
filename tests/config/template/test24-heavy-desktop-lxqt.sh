#!/bin/bash
# Template test (HEAVY): LXQt desktop
# Skipped by default; use --heavy to include.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "lxqt"

booth-collect "
echo -n '1: ' ; command -v startlxqt   >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v start-lxqt  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "LXQt session is installed"
assert-line "$tmpfile" "2: " "OK"  "start-lxqt launcher exists"
finally
