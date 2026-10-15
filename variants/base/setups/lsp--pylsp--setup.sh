#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--pylsp--setup.sh — Install pylsp, the Python language server (pip: python-lsp-server).
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest python-lsp-server
  $0 --version 1.15.0      # pin a release

Notes:
- Installs python-lsp-server into the booth's Python (/opt/python) with pip
- Links /usr/local/bin/pylsp, so an editor started without a login shell finds it
- Needs Python: select the python template (or run python--setup.sh first)
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

if [[ ! -x /opt/python/bin/pip ]]; then
  echo "❌ python-lsp-server needs the booth's Python, and /opt/python/bin/pip is missing." >&2
  echo "   Select the python template in booth config, then rebuild the booth." >&2
  exit 1
fi

if [[ "$REQ_VER" == "latest" ]]; then
  SPEC="python-lsp-server"
else
  SPEC="python-lsp-server==${REQ_VER}"
fi

echo "⬇️  Installing ${SPEC} ..."
pip--install.sh "$SPEC"
ln -sfn /opt/python/bin/pylsp /usr/local/bin/pylsp

echo "✅ pylsp installed."
echo -n "   pylsp → "; pylsp --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: pylsp
- Fresh, Helix, and neovim+lsp pick it up for Python files

Notes:
- Plugins (rope, black, ruff, mypy) install beside it: pip install "python-lsp-server[all]"
- See: https://github.com/python-lsp/python-lsp-server
EON
