#!/bin/bash
# Python turtle actually draws: square.py writes a PostScript file under Xvfb.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=/tmp/cb-turtle-square.ps
rm -f "$OUT"
echo "=== Testing python turtle draws a square ==="
xvfb-run -a python square.py --output "$OUT"
test -s "$OUT"
grep -q '%!PS' "$OUT"
echo "Wrote $(wc -c < "$OUT") bytes to $OUT"
