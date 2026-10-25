#!/bin/bash
echo "=== Testing Neovim + lean.nvim start the Lean server on a .lean file ==="
cd "$(dirname "$0")/.."
cat > /tmp/lean-nvim-check.lua <<'LUA'
local ok = vim.wait(180000, function()
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
     and #vim.diagnostic.get(0) > 0
end, 500)
local names = {}
for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do table.insert(names, c.name) end
local msgs = {}
for _, d in ipairs(vim.diagnostic.get(0)) do table.insert(msgs, d.message) end
io.stdout:write(("FILETYPE=%s CLIENTS=%s READY=%s\n"):format(vim.bo.filetype, table.concat(names, ","), tostring(ok)))
io.stdout:write("DIAGNOSTICS=" .. table.concat(msgs, " | ") .. "\n")
vim.cmd("qa!")
LUA
out="$(timeout 300 nvim --headless Exercises/Basic.lean -c 'luafile /tmp/lean-nvim-check.lua' 2>&1)"
echo "$out" | head -5
fail=0
[[ "$out" == *"FILETYPE=lean"* ]] && echo "  ✓ .lean files open as filetype lean" || { echo "  ✗ filetype"; fail=1; }
[[ "$out" == *"READY=true"* && "$out" == *"CLIENTS=lean"* ]] && echo "  ✓ the Lean language server attached" \
    || { echo "  ✗ no Lean language server attached"; fail=1; }
[[ "$out" == *"sorry"* ]] && echo "  ✓ its diagnostics reach Neovim" || { echo "  ✗ no diagnostics"; fail=1; }
exit $fail
