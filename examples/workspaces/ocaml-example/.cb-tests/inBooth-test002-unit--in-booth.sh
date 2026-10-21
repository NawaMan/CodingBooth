#!/bin/bash
set -euo pipefail
echo "=== Testing calc (dune test) ==="
cd "$(dirname "$0")/.."
just test 2>&1 | tee /tmp/ocaml-test.out
grep -q "All calc tests passed." /tmp/ocaml-test.out
