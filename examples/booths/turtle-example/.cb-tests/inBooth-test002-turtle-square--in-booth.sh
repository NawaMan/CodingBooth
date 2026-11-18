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
# A blank canvas is valid PostScript too, with one lineto (the clip box).
# The square adds its four sides.
lines=$(grep -c lineto "$OUT" || true)
if [ "$lines" -lt 5 ]; then
    echo "FAIL: only $lines lineto in $OUT - the square was not drawn" >&2
    exit 1
fi
echo "Wrote $(wc -c < "$OUT") bytes to $OUT"
