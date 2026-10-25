#!/bin/bash
echo "=== Testing elan + the pinned Lean toolchain ==="
cd "$(dirname "$0")/.."
pin="$(tr -d '[:space:]' < lean-toolchain)"            # leanprover/lean4:v4.35.0
want="${pin##*:v}"
lean --version | grep -q "version ${want}" || { echo "expected Lean ${want}, got: $(lean --version)"; exit 1; }
lake --version | grep -q "Lean version ${want})" || { echo "lake is not from Lean ${want}: $(lake --version)"; exit 1; }
# Baked in by lean+toolchain-file: installed, so nothing is downloaded at first use.
elan toolchain list | grep -qF "$pin" || { echo "pin ${pin} is not installed:"; elan toolchain list; exit 1; }
echo "  ✓ Lean ${want} (from lean-toolchain), elan $(elan --version | awk '{print $2}')"
