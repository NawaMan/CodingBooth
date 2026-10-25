#!/bin/bash
echo "=== Testing that a false theorem is rejected ==="
# A checker that accepts everything would pass test002 too; this is the other half.
cd "$(dirname "$0")/.."
bad="$(mktemp -d)/Bad.lean"
cat > "$bad" <<'LEAN'
import LeanExample
open LeanExample
theorem wrong : sumTo 4 = 11 := by decide
LEAN
if out="$(just check "$bad" 2>&1)"; then
    echo "  ✗ a false theorem was accepted:"; echo "$out"; exit 1
fi
echo "$out" | grep -q "error" || { echo "  ✗ failed without a Lean error:"; echo "$out"; exit 1; }
echo "  ✓ sumTo 4 = 11 is rejected"
