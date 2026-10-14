#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--bash--setup.sh — Install the Bash language server (npm: bash-language-server).
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest bash-language-server
  $0 --version 5.8.1   # pin a release

Notes:
- Installs bash-language-server globally with npm, so bash-language-server lands in /usr/local/bin
- Also installs shellcheck (apt), which the server runs for its diagnostics
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
  echo "❌ bash-language-server needs Node.js, and npm is not on PATH." >&2
  echo "   Select the nodejs template in booth config, then rebuild the booth." >&2
  exit 1
fi

echo "⬇️  Installing bash-language-server@${REQ_VER} ..."
npm--install.sh "bash-language-server@${REQ_VER}"

# bash-language-server's diagnostics come from shellcheck; without it the server
# still completes and hovers, but never flags anything.
if ! command -v shellcheck >/dev/null 2>&1; then
  apt--install.sh shellcheck
fi

echo "✅ Bash language server installed."
echo -n "   bash-language-server → "; command -v bash-language-server || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: bash-language-server start
- Fresh, Helix, and neovim+lsp pick it up for shell scripts

Notes:
- See: https://github.com/bash-lsp/bash-language-server
EON
