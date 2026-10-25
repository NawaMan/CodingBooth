#!/bin/bash
echo "=== Checking the proofs and running the program ==="
cd "$(dirname "$0")/.."
fail=0
just build 2>&1 | tee /tmp/lean-build.out
grep -q "Build completed successfully" /tmp/lean-build.out || { echo "  ✗ lake build failed"; fail=1; }
# A proof left as `sorry` still builds, with only a warning; it must not be there.
if grep -qi "sorry" /tmp/lean-build.out; then echo "  ✗ a proof uses sorry"; fail=1; else echo "  ✓ no sorry"; fi

got="$(just run 30 2>&1)"
for want in "sumTo 30 = 465 = 30 * 31 / 2" "fastFib 30 = 832040"; do
    if [[ "$got" == *"$want"* ]]; then echo "  ✓ $want"; else echo "  ✗ expected '$want', got: $got"; fail=1; fi
done
exit $fail
