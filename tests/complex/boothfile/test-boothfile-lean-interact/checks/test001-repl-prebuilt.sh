#!/bin/bash
echo "=== Testing the Lean REPL was built into the image ==="
cd "$(dirname "$0")/.."
version="$(tr -d '[:space:]' < lean-toolchain)"; version="${version##*:}"     # v4.35.0
repl="$(find /opt/lean-interact/cache -path "*/repl_*_lean-toolchain-${version}/.lake/build/bin/repl" -type f | head -1)"
[[ -n "$repl" && -x "$repl" ]] || { echo "  ✗ no prebuilt REPL for ${version} under /opt/lean-interact/cache"; exit 1; }
echo "  ✓ prebuilt REPL for ${version}"
# LeanInteract's own cache folder must lead there, or it would build a second copy.
target="$(python -c 'import lean_interact, os; print(os.path.realpath(os.path.join(os.path.dirname(lean_interact.__file__), "cache")))')"
[[ "$target" == /opt/lean-interact/cache ]] || { echo "  ✗ lean_interact cache is $target"; exit 1; }
echo "  ✓ lean_interact's cache is /opt/lean-interact/cache"
