#!/bin/bash
set -euo pipefail
echo "=== Testing UTop with the calc library loaded ==="
cd "$(dirname "$0")/.."
printf 'Calc.calculate "6 * 7";;\n#quit;;\n' | dune utop src 2>&1 | tee /tmp/ocaml-utop.out
grep -q '"(6 \* 7) = 42"' /tmp/ocaml-utop.out
