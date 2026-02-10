#!/bin/bash
# Template test (HEAVY): XFCE desktop + VS Code + Browsers
# This test installs a full desktop environment — expect long build times.
# Skipped by default; use --heavy to include.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "xfce/vscode/chromium/firefox/google-chrome"

booth-collect "
echo -n '1: ' ; command -v startxfce4      >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v start-xfce      >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; test -x /usr/local/bin/code                && echo 'OK' || echo 'FAIL' ;
echo -n '4: ' ; command -v chromium         >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '5: ' ; command -v firefox          >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '6: ' ; command -v google-chrome    >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "XFCE session is installed"
assert-line "$tmpfile" "2: " "OK"  "start-xfce launcher exists"
assert-line "$tmpfile" "3: " "OK"  "VS Code is installed"
assert-line "$tmpfile" "4: " "OK"  "Chromium is installed"
assert-line "$tmpfile" "5: " "OK"  "Firefox is installed"
assert-line "$tmpfile" "6: " "OK"  "Google Chrome is installed"
finally
