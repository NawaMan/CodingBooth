#!/bin/bash
# Template test: Erlang + Elixir (BEAM VM)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "erlang/elixir"

booth-collect "
echo -n '1: ' ; command -v erl    >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v elixir >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Erlang is installed"
assert-line "$tmpfile" "2: " "OK"  "Elixir is installed"
finally
