#!/bin/bash
# Template test: R (statistics)
# Note: Erlang/Elixir excluded — erlang--setup.sh kerl build exits 1 due to
#       OpenSSL crypto warning (pre-existing). See test05b for that pair.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "r"

booth-collect "
echo -n '1: ' ; command -v Rscript >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "R is installed"
finally
