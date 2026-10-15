#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--tailwindcss--setup.sh — Install the Tailwind CSS language server (npm: @tailwindcss/language-server).
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest @tailwindcss/language-server
  $0 --version 0.16.0   # pin a release

Notes:
- Installs @tailwindcss/language-server globally with npm, so tailwindcss-language-server lands in /usr/local/bin
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
  echo "❌ @tailwindcss/language-server needs Node.js, and npm is not on PATH." >&2
  echo "   Select the nodejs template in booth config, then rebuild the booth." >&2
  exit 1
fi

echo "⬇️  Installing @tailwindcss/language-server@${REQ_VER} ..."
npm--install.sh "@tailwindcss/language-server@${REQ_VER}"

echo "✅ Tailwind CSS language server installed."
echo -n "   tailwindcss-language-server → "; command -v tailwindcss-language-server || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: tailwindcss-language-server --stdio
- Fresh, Helix, and neovim+lsp pick it up for Tailwind CSS classes

Notes:
- See: https://github.com/tailwindlabs/tailwindcss-intellisense
EON
