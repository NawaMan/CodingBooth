#!/bin/bash
# Run every cell of Latency.ipynb on the conda kernel; any cell error fails.
echo "=== Testing Latency.ipynb on the conda kernel ==="
set -euo pipefail
cd "$(dirname "$0")/.."
OUT_DIR="$(mktemp -d)"
jupyter nbconvert --to notebook --execute Latency.ipynb --output-dir "$OUT_DIR" --output Latency
grep -q '"image/png"' "$OUT_DIR/Latency.ipynb"
grep -q 'GET /api/search' "$OUT_DIR/Latency.ipynb"
