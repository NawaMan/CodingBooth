#!/bin/bash
echo "=== Testing the proof search script ==="
cd "$(dirname "$0")/.."
out="$(just search 2>&1)"; echo "$out"
fail=0
for want in "✓ ∀ a b : Nat, a + b = b + a" "✗ ∀ n : Nat, n + 1 ≤ n * n" "6 of 7 proved"; do
    if [[ "$out" == *"$want"* ]]; then echo "  ✓ $want"; else echo "  ✗ missing: $want"; fail=1; fi
done
exit $fail
