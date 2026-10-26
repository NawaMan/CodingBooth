#!/bin/bash
echo "=== Testing that checkdecls rejects a name Lean does not have ==="
# The other half of test002: a check that passes everything proves nothing.
cd "$(dirname "$0")/.."
bad="$(mktemp)"
printf 'OddSquares.oddSum\nOddSquares.noSuchTheorem\n' > "$bad"
if out="$(lake exe checkdecls "$bad" 2>&1)"; then
    echo "  ✗ checkdecls accepted OddSquares.noSuchTheorem:"; echo "$out"; exit 1
fi
echo "$out" | grep -q "noSuchTheorem" || { echo "  ✗ failed without naming it:"; echo "$out"; exit 1; }
echo "  ✓ OddSquares.noSuchTheorem is rejected"
