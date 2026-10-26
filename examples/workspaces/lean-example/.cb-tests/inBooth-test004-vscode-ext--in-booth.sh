#!/bin/bash
echo "=== Testing the Lean 4 VS Code extension ==="
# Setups install extensions into the image-wide directory, not the user's own.
dir=/usr/local/share/code-server/extensions
code-server --extensions-dir "$dir" --list-extensions 2>/dev/null | grep -qi '^leanprover.lean4$' \
    || { echo "  ✗ leanprover.lean4 not installed in $dir:"; ls "$dir"; exit 1; }
echo "  ✓ leanprover.lean4 installed in code-server"
