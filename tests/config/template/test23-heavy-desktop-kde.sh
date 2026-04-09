#!/bin/bash
# Template test (HEAVY): KDE desktop + JetBrains IDEs + Eclipse + Warp
# This test installs a full KDE desktop plus several IDEs — very long build.
# Skipped by default; use --heavy to include.
# Note: idea, pycharm, eclipse, and warp require a desktop to install.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "java:21/kde/idea/pycharm/eclipse/warp"

booth-collect "
echo -n '1: ' ; command -v startplasma-x11  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v start-kde        >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; test -x /usr/local/bin/eclipse               && echo 'OK' || echo 'FAIL' ;
echo -n '4: ' ; command -v warp-terminal    >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "KDE Plasma is installed"
assert-line "$tmpfile" "2: " "OK"  "start-kde launcher exists"
assert-line "$tmpfile" "3: " "OK"  "Eclipse is installed"
assert-line "$tmpfile" "4: " "OK"  "Warp terminal is installed"
finally
