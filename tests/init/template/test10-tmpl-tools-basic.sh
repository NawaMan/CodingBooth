#!/bin/bash
# Template test: GitHub CLI (lightweight tools)
# Note: Neovim excluded — neovim--setup.sh downloads old asset name (nvim-linux64.tar.gz)
#       that no longer exists; neovim renamed to nvim-linux-x86_64.tar.gz (pre-existing).
#       See test06b for neovim.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "gh"

booth-collect "
echo -n '1: ' ; command -v gh >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "GitHub CLI is installed"
finally
