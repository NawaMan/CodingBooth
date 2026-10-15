#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--docker-compose--setup.sh — Install the Docker Compose language server (npm: @microsoft/compose-language-service).
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest @microsoft/compose-language-service
  $0 --version 1.0.0   # pin a release

Notes:
- Installs @microsoft/compose-language-service globally with npm, so docker-compose-langserver lands in /usr/local/bin
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
  echo "❌ @microsoft/compose-language-service needs Node.js, and npm is not on PATH." >&2
  echo "   Select the nodejs template in booth config, then rebuild the booth." >&2
  exit 1
fi

echo "⬇️  Installing @microsoft/compose-language-service@${REQ_VER} ..."
npm--install.sh "@microsoft/compose-language-service@${REQ_VER}"

echo "✅ Docker Compose language server installed."
echo -n "   docker-compose-langserver → "; command -v docker-compose-langserver || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: docker-compose-langserver --stdio
- Fresh, Helix, and neovim+lsp pick it up for compose.yaml files (Helix, neovim+lsp)

Notes:
- See: https://github.com/microsoft/compose-language-service
EON
