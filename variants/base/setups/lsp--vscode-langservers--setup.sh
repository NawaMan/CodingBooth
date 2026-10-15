#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--vscode-langservers--setup.sh — Install the JSON, HTML, and CSS language servers from VS Code (npm: vscode-langservers-extracted).
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest vscode-langservers-extracted
  $0 --version 4.10.0   # pin a release

Notes:
- Installs vscode-langservers-extracted globally with npm, so vscode-json-language-server vscode-html-language-server vscode-css-language-server lands in /usr/local/bin
- Needs Node.js: select the nodejs template (or run nodejs--setup.sh first)
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

if ! command -v npm >/dev/null 2>&1; then
  echo "❌ vscode-langservers-extracted needs Node.js, and npm is not on PATH." >&2
  echo "   Select the nodejs template in booth config, then rebuild the booth." >&2
  exit 1
fi

echo "⬇️  Installing vscode-langservers-extracted@${REQ_VER} ..."
npm--install.sh "vscode-langservers-extracted@${REQ_VER}"

echo "✅ JSON, HTML, and CSS language servers from VS Code installed."
echo -n "   vscode-json-language-server → "; command -v vscode-json-language-server || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: vscode-json-language-server --stdio (and -html, -css)
- Fresh, Helix, and neovim+lsp pick it up for JSON, HTML, and CSS files

Notes:
- See: https://github.com/hrsh7th/vscode-langservers-extracted
EON
