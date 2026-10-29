#!/bin/bash
echo "=== Testing the Lean 4 VS Code extension ==="
# Only a codeserver booth has code-server; a base booth (as on GHA) skips this test.
command -v code-server >/dev/null || { echo "  - skipped: no code-server here"; exit 0; }
# Setups install extensions into the image-wide directory, not the user's own.
dir=/usr/local/share/code-server/extensions
code-server --extensions-dir "$dir" --list-extensions 2>/dev/null | grep -qi '^leanprover.lean4$' \
    || { echo "  ✗ leanprover.lean4 not installed in $dir:"; ls "$dir"; exit 1; }
echo "  ✓ leanprover.lean4 installed in code-server"
