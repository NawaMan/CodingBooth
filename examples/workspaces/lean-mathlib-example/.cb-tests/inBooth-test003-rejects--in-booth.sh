#!/bin/bash
echo "=== Testing that Mathlib does not prove a false statement ==="
cd "$(dirname "$0")/.."
bad="$(mktemp -d)/Bad.lean"
cat > "$bad" <<'LEAN'
import Mathlib
-- False: √2 is irrational, so no rational number squares to 2.
theorem bad : ∃ q : ℚ, q ^ 2 = 2 := ⟨3 / 2, by norm_num⟩
LEAN
if out="$(just check "$bad" 2>&1)"; then
    echo "  ✗ a false theorem was accepted:"; echo "$out"; exit 1
fi
echo "$out" | grep -q "error" || { echo "  ✗ failed without a Lean error:"; echo "$out"; exit 1; }
echo "  ✓ (3/2)² = 2 is rejected"
