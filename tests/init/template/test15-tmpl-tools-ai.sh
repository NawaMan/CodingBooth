#!/bin/bash
# Template test: Claude Code + Codex (AI coding tools)
# Both need Node.js (npm), so nodejs is included.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth init new $prj --select "nodejs/claude-code/codex"

booth-collect "
echo -n '1: ' ; command -v claude >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v codex  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Claude Code is installed"
assert-line "$tmpfile" "2: " "OK"  "Codex is installed"
finally
