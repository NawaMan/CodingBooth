#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lean-lsp-mcp--setup.sh — Install lean-lsp-mcp, an MCP server that gives AI agents
# (Claude Code, Codex, …) Lean's goals, errors and search, through the Lean language server.
# EXPERIMENTAL: new, not yet battle-tested.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>]

Examples:
  $0                     # the pinned lean-lsp-mcp release
  $0 --version 0.31.0    # a specific release

Notes:
- Installs into its own virtualenv (/opt/lean-lsp-mcp) on the system Python, so it does
  not depend on, or disturb, the python template's environment. The command lands at
  /usr/local/bin/lean-lsp-mcp.
- Also installs ripgrep, which its local search tool (lean_local_search) uses.
- The server runs `lake serve` in the Lean project, so run `lake build` once first.
- Register it per project: a .mcp.json with {"mcpServers": {"lean-lsp": {"command":
  "lean-lsp-mcp"}}}, or `claude mcp add lean-lsp lean-lsp-mcp`.
- See: https://github.com/oOo0oOo/lean-lsp-mcp
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

VERSION="0.31.0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; VERSION="${1:?--version needs a value}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a lean-lsp-mcp version: '${VERSION}' (expected X.Y.Z)" >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3 python3-venv ripgrep
rm -rf /var/lib/apt/lists/*

VENV=/opt/lean-lsp-mcp
echo "⬇️  Installing lean-lsp-mcp ${VERSION} into ${VENV} ..."
rm -rf "$VENV"
/usr/bin/python3 -m venv "$VENV"
env PIP_CACHE_DIR="${PIP_CACHE_DIR:-}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "$VENV/bin/pip" install "lean-lsp-mcp==${VERSION}" >/dev/null
ln -sf "$VENV/bin/lean-lsp-mcp" /usr/local/bin/lean-lsp-mcp

lean-lsp-mcp --help >/dev/null

echo "✅ lean-lsp-mcp installed."
echo "   lean-lsp-mcp → $("$VENV/bin/pip" show lean-lsp-mcp 2>/dev/null | sed -n 's/^Version: //p')"

cat <<'EON'
ℹ️ Ready to use (in a Lean project, after `lake build`):
- Claude Code:  claude mcp add lean-lsp lean-lsp-mcp      (or a project .mcp.json)
- Tools:        lean_goal, lean_diagnostic_messages, lean_hover_info, lean_local_search, …
- Docs:         https://github.com/oOo0oOo/lean-lsp-mcp
EON
