#!/bin/bash
set -euo pipefail
echo "=== Testing the sources are OCamlFormat-clean ==="
cd "$(dirname "$0")/.."
dune build @fmt
