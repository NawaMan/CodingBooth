#!/bin/bash
# Template test: XFCE + LibreOffice (desktop office suite)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "xfce/libreoffice"

booth-collect "
echo -n '1: ' ; command -v libreoffice >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "LibreOffice is installed"
finally
