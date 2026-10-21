#!/bin/bash
set -euo pipefail
echo "=== Testing the calc CLI ==="
cd "$(dirname "$0")/.."
[[ "$(just run "(1 + 2) * 3")" == "((1 + 2) * 3) = 9" ]]
[[ "$(just run 1 + 2 '*' 3)" == "(1 + (2 * 3)) = 7" ]]
if just run "1 / 0" 2>/tmp/ocaml-cli.err; then
    echo "division by zero should fail" >&2; exit 1
fi
grep -q "division by zero" /tmp/ocaml-cli.err
