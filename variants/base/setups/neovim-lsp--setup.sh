#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

# neovim-lsp--setup.sh — Enable Neovim's built-in LSP client for the booth's language servers.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Writes /usr/local/share/nvim/site/plugin/booth-lsp.lua, which Neovim loads for every
  user from its system runtime path, after the user's own init.lua
- At startup it enables each known server that is on PATH (the lsp template's, plus
  gopls, rust-analyzer, clangd, and the haskell template's HLS), through vim.lsp.config / vim.lsp.enable (Neovim 0.11+)
- Opt out from your own config with: vim.g.booth_lsp = false
- No plugin manager, no nvim-lspconfig needed; with nvim-lspconfig installed the
  two configs merge
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
esac

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

PLUGIN_DIR="/usr/local/share/nvim/site/plugin"
mkdir -p "$PLUGIN_DIR"
cat > "${PLUGIN_DIR}/booth-lsp.lua" <<'LUA'
-- Written by neovim-lsp--setup.sh (CodingBooth). Enables Neovim's built-in LSP
-- client for every language server from the lsp template that is on PATH.
-- Opt out in your own init.lua with: vim.g.booth_lsp = false
if vim.g.booth_lsp == false or vim.fn.has('nvim-0.11') == 0 then
  return
end

local servers = {
  marksman     = { cmd = { 'marksman', 'server' },                  filetypes = { 'markdown' },          root_markers = { '.marksman.toml', '.git' } },
  taplo        = { cmd = { 'taplo', 'lsp', 'stdio' },               filetypes = { 'toml' },              root_markers = { '.taplo.toml', 'taplo.toml', '.git' } },
  terraformls  = { cmd = { 'terraform-ls', 'serve' },               filetypes = { 'terraform', 'terraform-vars', 'hcl' }, root_markers = { '.terraform', '.git' } },
  sqls         = { cmd = { 'sqls' },                                filetypes = { 'sql', 'mysql' },      root_markers = { 'config.yml', '.git' } },
  yamlls       = { cmd = { 'yaml-language-server', '--stdio' },     filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab' }, root_markers = { '.git' } },
  bashls       = { cmd = { 'bash-language-server', 'start' },       filetypes = { 'sh', 'bash' },        root_markers = { '.git' } },
  jsonls       = { cmd = { 'vscode-json-language-server', '--stdio' }, filetypes = { 'json', 'jsonc' },  root_markers = { '.git' } },
  html         = { cmd = { 'vscode-html-language-server', '--stdio' }, filetypes = { 'html' },          root_markers = { 'package.json', '.git' } },
  cssls        = { cmd = { 'vscode-css-language-server', '--stdio' },  filetypes = { 'css', 'scss', 'less' }, root_markers = { 'package.json', '.git' } },
  ts_ls        = { cmd = { 'typescript-language-server', '--stdio' },
                   filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
                   root_markers = { 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' } },
  tailwindcss  = { cmd = { 'tailwindcss-language-server', '--stdio' },
                   filetypes = { 'html', 'css', 'javascriptreact', 'typescriptreact', 'vue', 'svelte' },
                   root_markers = { 'tailwind.config.js', 'tailwind.config.ts', 'tailwind.config.cjs', 'postcss.config.js' } },
  dockerls     = { cmd = { 'docker-langserver', '--stdio' },        filetypes = { 'dockerfile' },        root_markers = { 'Dockerfile', '.git' } },
  docker_compose_language_service = {
                   cmd = { 'docker-compose-langserver', '--stdio' }, filetypes = { 'yaml.docker-compose' },
                   root_markers = { 'compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml' } },
  jdtls        = { cmd = { 'jdtls' },                               filetypes = { 'java' },
                   root_markers = { 'pom.xml', 'build.gradle', 'build.gradle.kts', 'settings.gradle', '.git' } },
  svelte       = { cmd = { 'svelteserver', '--stdio' },             filetypes = { 'svelte' },            root_markers = { 'package.json', '.git' } },
  -- From the language templates (or lsp+c for clangd) rather than the lsp template.
  gopls        = { cmd = { 'gopls' },                               filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
                   root_markers = { 'go.work', 'go.mod', '.git' } },
  rust_analyzer = { cmd = { 'rust-analyzer' },                      filetypes = { 'rust' },              root_markers = { 'Cargo.toml', '.git' } },
  clangd       = { cmd = { 'clangd' },                              filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
                   root_markers = { 'compile_commands.json', 'compile_flags.txt', '.clangd', '.git' } },
  pylsp        = { cmd = { 'pylsp' },                               filetypes = { 'python' },
                   root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git' } },
  hls          = { cmd = { 'haskell-language-server-wrapper', '--lsp' }, filetypes = { 'haskell', 'lhaskell', 'cabal' },
                   root_markers = { 'hie.yaml', 'stack.yaml', 'cabal.project', 'package.yaml', '.git' } },
  zls          = { cmd = { 'zls' },                                 filetypes = { 'zig', 'zir' },
                   root_markers = { 'zls.json', 'build.zig', '.git' } },
}

for name, config in pairs(servers) do
  if vim.fn.executable(config.cmd[1]) == 1 then
    vim.lsp.config(name, config)
    vim.lsp.enable(name)
  end
end
LUA
chmod 644 "${PLUGIN_DIR}/booth-lsp.lua"

echo "✅ Neovim LSP wiring installed."
echo "   ${PLUGIN_DIR}/booth-lsp.lua"

cat <<'EON'
ℹ️ Ready to use:
- Open a file whose server is installed: nvim README.md
- See what attached:  :checkhealth vim.lsp
- Opt out:            vim.g.booth_lsp = false   (in your init.lua)

Notes:
- Servers come from the lsp template (lsp+markdown, lsp:taplo,yaml, ...).
- Needs Neovim 0.11 or newer; older versions skip the file.
EON
