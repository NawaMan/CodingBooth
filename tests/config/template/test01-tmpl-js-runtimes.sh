#!/bin/bash
# Template test: Node.js + Bun + Deno (JS/TS runtimes)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "nodejs/bun/deno"

booth-collect "
echo -n '1: ' ; command -v node >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v bun  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; command -v deno >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Node.js is installed"
assert-line "$tmpfile" "2: " "OK"  "Bun is installed"
assert-line "$tmpfile" "3: " "OK"  "Deno is installed"
finally
