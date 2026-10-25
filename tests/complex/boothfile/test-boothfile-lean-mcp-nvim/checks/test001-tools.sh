#!/bin/bash
echo "=== Testing the tools are installed ==="
cd "$(dirname "$0")/.."
fail=0
for cmd in lean lake nvim lean-lsp-mcp rg; do
    if command -v "$cmd" >/dev/null; then echo "  ✓ $cmd"; else echo "  ✗ $cmd not on PATH"; fail=1; fi
done
exit $fail
