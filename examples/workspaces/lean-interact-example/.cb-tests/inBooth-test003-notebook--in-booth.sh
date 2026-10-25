#!/bin/bash
echo "=== Testing the notebook runs top to bottom ==="
cd "$(dirname "$0")/.."
out="$(just notebook 2>&1)"
fail=0
for want in "valid: True" "valid: False" "is false" "oddSum 25 = 25²: True" "proof: Completed" "✗ ∀ n : Nat, n + 1 ≤ n * n"; do
    if [[ "$out" == *"$want"* ]]; then echo "  ✓ $want"; else echo "  ✗ missing: $want"; fail=1; fi
done
[[ $fail == 0 ]] || echo "$out" | tail -40
exit $fail
