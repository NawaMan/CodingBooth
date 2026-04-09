#!/bin/bash
# Template test: XFCE + Inkscape + GIMP (desktop graphics apps)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "xfce/inkscape/gimp"

booth-collect "
echo -n '1: ' ; command -v inkscape >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v gimp     >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Inkscape is installed"
assert-line "$tmpfile" "2: " "OK"  "GIMP is installed"
finally
