#!/bin/bash
echo "=== Testing Lean and Mathlib are pinned to the same release ==="
cd "$(dirname "$0")/.."
pin="$(tr -d '[:space:]' < lean-toolchain)"; want="${pin##*:}"                     # v4.35.0
lean --version | grep -q "version ${want#v}" || { echo "  ✗ lean is not ${want}: $(lean --version)"; exit 1; }
grep -q "rev = \"${want}\"" lakefile.toml || { echo "  ✗ lakefile.toml does not pin mathlib to ${want}"; exit 1; }
echo "  ✓ Lean ${want}, Mathlib ${want}"
