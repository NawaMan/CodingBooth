#!/bin/bash
# Template test: Go + Rust (compiled systems languages)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "go/rust"

booth-collect "
echo -n '1: ' ; command -v go     >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v rustc  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; command -v cargo  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '4: ' ; command -v gopls  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '5: ' ; command -v dlv    >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Go is installed"
assert-line "$tmpfile" "2: " "OK"  "Rust (rustc) is installed"
assert-line "$tmpfile" "3: " "OK"  "Cargo is installed"
assert-line "$tmpfile" "4: " "OK"  "gopls is installed"
assert-line "$tmpfile" "5: " "OK"  "delve (dlv) is installed"
finally
