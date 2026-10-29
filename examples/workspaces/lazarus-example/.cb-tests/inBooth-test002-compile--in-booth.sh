#!/bin/bash
set -euo pipefail
# fpc compiles and runs a Pascal program (no GUI needed).
echo "=== Testing fpc compile ==="
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'program h;\nbegin\n  writeln("hello from fpc");\nend.\n' | sed "s/\"/'/g" > "$tmp/h.pas"
fpc -FE"$tmp" "$tmp/h.pas" >/dev/null
"$tmp/h" | grep -q "hello from fpc"
