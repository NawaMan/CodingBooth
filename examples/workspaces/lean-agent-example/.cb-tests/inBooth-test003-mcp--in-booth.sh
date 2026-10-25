#!/bin/bash
echo "=== Testing the Lean MCP server answers like it does for Claude Code ==="
cd "$(dirname "$0")/.."
# The line of the sorry in two_mul_sumTo: the goal there is Gauss's formula.
line="$(grep -n 'theorem two_mul_sumTo' Exercises/Basic.lean | cut -d: -f1)"; line=$((line + 1))
out="$(timeout 600 /opt/lean-lsp-mcp/bin/python .cb-tests/mcp_check.py Exercises/Basic.lean "$line" 2>&1)"
fail=0
check() { if [[ "$out" == *"$2"* ]]; then echo "  ✓ $1"; else echo "  ✗ $1 (no '$2')"; fail=1; fi; }
check "lists lean_goal"                  "lean_goal"
check "goal at the sorry is Gauss's"     "2 * sumTo n = n * (n + 1)"
check "diagnostics report the sorry"     "sorry"
[[ $fail == 0 ]] || echo "$out" | tail -30
exit $fail
