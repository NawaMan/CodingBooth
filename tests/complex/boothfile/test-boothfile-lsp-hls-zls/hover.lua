-- nvim --headless <file> -c "lua HOVER_AT={<line>,<col>}" -c "luafile hover.lua"   (0-based)
-- Waits for neovim+lsp's client to attach, asks it for hover at <line>:<col>,
-- and prints "<client>: <first line of the hover text>", or "none" / "no-hover".
local line, col = HOVER_AT[1], HOVER_AT[2]
local function client()
  local c = vim.lsp.get_clients({ bufnr = 0 })[1]
  return c and c.initialized and c or nil
end
if not vim.wait(120000, function() return client() ~= nil end, 500) then
  io.stdout:write("none\n"); vim.cmd("qa!")
end
local c, text = client(), nil
-- A server may answer null until it has loaded the module; ask again until it knows.
vim.wait(180000, function()
  local r = vim.lsp.buf_request_sync(0, "textDocument/hover", {
    textDocument = vim.lsp.util.make_text_document_params(0),
    position = { line = line, character = col },
  }, 10000)
  for _, res in pairs(r or {}) do
    local v = res.result and res.result.contents
    v = type(v) == "table" and (v.value or v[1]) or v
    if type(v) == "string" and v:find("greet") then text = v; return true end
  end
  return false
end, 3000)
local first = text and (text:gsub("```%w*", ""):match("[^\n]*greet[^\n]*")) or "no-hover"
io.stdout:write(c.name .. ": " .. vim.trim(first) .. "\n")
vim.cmd("qa!")
