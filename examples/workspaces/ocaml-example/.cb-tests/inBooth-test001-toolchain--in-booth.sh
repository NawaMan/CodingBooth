#!/bin/bash
set -euo pipefail
echo "=== Testing the OCaml toolchain ==="
ocaml -version | grep -q "5.4.1"
dune --version
utop -version
ocamlformat --version
opam switch show | grep -qx booth
