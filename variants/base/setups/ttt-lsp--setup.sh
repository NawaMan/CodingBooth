#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.1

# ttt-lsp--setup.sh — Point TTT at the booth's language servers.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- TTT starts only the servers listed under lsp.servers in ~/.config/ttt/settings.json
- Writes /usr/share/startup.d/74-cb-ttt-lsp--startup.sh, which at each container start
  adds an entry for every known server that is on PATH and has none yet
- An entry is added once: delete it and it stays deleted (~/.config/ttt/.booth-lsp-added)
- Entries you wrote yourself are never changed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
esac

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# The servers the lsp template installs, plus gopls, rust-analyzer, and HLS from the
# language templates. The keys and language maps follow TTT's own lsp-* plugins;
# python is pylsp here, because that is what the booth installs.
SERVERS_FILE=/opt/codingbooth/ttt/booth-lsp-servers.json
install -d "$(dirname "$SERVERS_FILE")"
cat > "$SERVERS_FILE" <<'JSON'
{
  "markdown":    { "command": ["marksman", "server"],                      "languages": { ".md": "markdown", ".markdown": "markdown" } },
  "toml":        { "command": ["taplo", "lsp", "stdio"],                   "languages": { ".toml": "toml" } },
  "terraform":   { "command": ["terraform-ls", "serve"],                   "languages": { ".tf": "terraform", ".tfvars": "terraform" } },
  "sql":         { "command": ["sqls"],                                    "languages": { ".sql": "sql" } },
  "yaml":        { "command": ["yaml-language-server", "--stdio"],         "languages": { ".yaml": "yaml", ".yml": "yaml" } },
  "bash":        { "command": ["bash-language-server", "start"],           "languages": { ".sh": "sh", ".bash": "bash" } },
  "json":        { "command": ["vscode-json-language-server", "--stdio"],  "languages": { ".json": "json", ".jsonc": "jsonc" } },
  "html":        { "command": ["vscode-html-language-server", "--stdio"],  "languages": { ".html": "html", ".htm": "html" } },
  "css":         { "command": ["vscode-css-language-server", "--stdio"],   "languages": { ".css": "css", ".scss": "scss", ".less": "less" } },
  "typescript":  { "command": ["typescript-language-server", "--stdio"],
                   "languages": { ".ts": "typescript", ".tsx": "typescriptreact", ".js": "javascript", ".jsx": "javascriptreact",
                                  ".mjs": "javascript", ".mts": "typescript", ".cjs": "javascript", ".cts": "typescript" } },
  "svelte":      { "command": ["svelteserver", "--stdio"],                 "languages": { ".svelte": "svelte" } },
  "tailwindcss": { "command": ["tailwindcss-language-server", "--stdio"] },
  "docker":      { "command": ["docker-langserver", "--stdio"] },
  "python":      { "command": ["pylsp"],                                   "languages": { ".py": "python", ".pyi": "python" } },
  "c":           { "command": ["clangd"],
                   "languages": { ".c": "c", ".h": "c", ".cpp": "cpp", ".hpp": "cpp", ".cc": "cpp", ".cxx": "cpp" } },
  "java":        { "command": ["jdtls"],                                   "languages": { ".java": "java" } },
  "go":          { "command": ["gopls"],                                   "languages": { ".go": "go" } },
  "rust":        { "command": ["rust-analyzer"],                           "languages": { ".rs": "rust" } },
  "haskell":     { "command": ["haskell-language-server-wrapper", "--lsp"], "languages": { ".hs": "haskell", ".lhs": "lhaskell" } },
  "zig":         { "command": ["zls"],                                     "languages": { ".zig": "zig" } }
}
JSON
chmod 644 "$SERVERS_FILE"

STARTUP_FILE=/usr/share/startup.d/74-cb-ttt-lsp--startup.sh
install -d "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
# Written by ttt-lsp--setup.sh (CodingBooth). Adds an lsp.servers entry to TTT's
# settings for each known server on PATH, once; see ttt-lsp--setup.sh --help.
set -uo pipefail

SERVERS=/opt/codingbooth/ttt/booth-lsp-servers.json
CONF="$HOME/.config/ttt/settings.json"
ADDED="$HOME/.config/ttt/.booth-lsp-added"
[[ -r "$SERVERS" ]] || exit 0

# Keys whose server is installed and that were never added before.
mapfile -t ADDED_KEYS < <(cat "$ADDED" 2>/dev/null)
NEW=()
for key in $(jq -r 'keys[]' "$SERVERS"); do
  printf '%s\n' "${ADDED_KEYS[@]}" | grep -qxF "$key" && continue
  command -v "$(jq -r --arg k "$key" '.[$k].command[0]' "$SERVERS")" >/dev/null 2>&1 || continue
  NEW+=("$key")
done
(( ${#NEW[@]} )) || exit 0

mkdir -p "$(dirname "$CONF")"
[[ -s "$CONF" ]] || echo '{"version":1}' > "$CONF"
tmp="$(mktemp)"
if jq --slurpfile s "$SERVERS" --args '
     reduce $ARGS.positional[] as $k (.;
       if .lsp.servers[$k] == null then .lsp.servers[$k] = $s[0][$k] else . end)' \
     "${NEW[@]}" < "$CONF" > "$tmp"; then
  mv "$tmp" "$CONF"
  printf '%s\n' "${NEW[@]}" >> "$ADDED"
else
  rm -f "$tmp"
  echo "⚠️  TTT language servers were not set; ${CONF} is not JSON." >&2
fi
STARTUP
chmod 755 "$STARTUP_FILE"

echo "✅ TTT LSP wiring installed."
echo "   ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Open a file whose server is installed: ttt README.md
- The status bar shows the server state: Markdown ◉ means connected

Notes:
- Servers come from the lsp template (lsp+markdown, lsp:taplo,yaml, ...) and the language templates.
- Delete an entry from lsp.servers to turn that server off; it is not added again.
EON
