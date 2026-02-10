#!/bin/bash
# Template test: Haskell + Free Pascal + Zig (compiled languages)
# Note: Lua excluded — lua--setup.sh has a readline linker bug that aborts the build.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "haskell/fpc/zig"

booth-collect "
echo -n '1: ' ; command -v ghc >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v fpc >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; command -v zig >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "GHC (Haskell) is installed"
assert-line "$tmpfile" "2: " "OK"  "Free Pascal is installed"
assert-line "$tmpfile" "3: " "OK"  "Zig is installed"
finally
