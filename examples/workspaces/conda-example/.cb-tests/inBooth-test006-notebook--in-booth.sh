#!/bin/bash
# Run every cell of Molecules.ipynb on the conda kernel; any cell error fails.
echo "=== Testing Molecules.ipynb on the conda kernel ==="
set -euo pipefail
cd "$(dirname "$0")/.."
OUT_DIR="$(mktemp -d)"
jupyter nbconvert --to notebook --execute Molecules.ipynb --output-dir "$OUT_DIR" --output Molecules
grep -q '/opt/conda-envs/' "$OUT_DIR/Molecules.ipynb"
grep -q '<svg' "$OUT_DIR/Molecules.ipynb"
