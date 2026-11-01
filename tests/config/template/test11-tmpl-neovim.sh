#!/bin/bash
# Template test: Neovim (standalone)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "neovim"

booth-collect "
echo -n '1: ' ; command -v nvim >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Neovim is installed"
finally
