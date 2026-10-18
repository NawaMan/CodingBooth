#!/bin/bash
echo "=== Testing Molecule Lab CLI ==="
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(just run caffeine)"
echo "$OUT"
echo "$OUT" | grep -q "Formula:        C8H10N4O2"
echo "$OUT" | grep -q "Lipinski:       pass"
just run rifampicin | grep -q "Lipinski:       FAIL"
