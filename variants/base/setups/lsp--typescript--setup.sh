#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--typescript--setup.sh — Install the TypeScript and JavaScript language server (npm: typescript-language-server).
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest typescript-language-server
  $0 --version 6.0.2   # pin a release

Notes:
- Installs typescript-language-server globally with npm, so typescript-language-server lands in /usr/local/bin
- Also installs typescript@^6 globally: the server needs tsserver.js, which TypeScript 7 dropped
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
  echo "❌ typescript-language-server needs Node.js, and npm is not on PATH." >&2
  echo "   Select the nodejs template in booth config, then rebuild the booth." >&2
  exit 1
fi

echo "⬇️  Installing typescript-language-server@${REQ_VER} ..."
# typescript-language-server drives tsserver.js, which TypeScript 7 (the native
# Go port) no longer ships: with typescript@latest it fails every initialize with
# "Could not find a valid TypeScript installation". Pin the last JS line. A
# project's own node_modules/typescript still wins over this one.
npm--install.sh "typescript-language-server@${REQ_VER}" "typescript@^6"

echo "✅ TypeScript and JavaScript language server installed."
echo -n "   typescript-language-server → "; command -v typescript-language-server || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: typescript-language-server --stdio
- Fresh, Helix, and neovim+lsp pick it up for TypeScript and JavaScript files

Notes:
- See: https://github.com/typescript-language-server/typescript-language-server
EON
