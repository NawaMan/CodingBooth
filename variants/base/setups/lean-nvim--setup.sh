#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lean-nvim--setup.sh — Install lean.nvim, Lean 4 support for Neovim: the language server,
# an infoview window with the goal at the cursor, and \alpha-style Unicode input.
# EXPERIMENTAL: new, not yet battle-tested.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <tag>]

Examples:
  $0                          # the pinned lean.nvim release
  $0 --version v2026.4.1      # a specific release tag

Notes:
- Needs Neovim 0.11 or newer (neovim--setup.sh).
- Installed system-wide as a Neovim package, with a plugin file that runs
  require("lean").setup { mappings = true } at startup -- no plugin manager needed. It
  loads after your own init.lua; set vim.g.booth_lean = false there to turn it off, or
  call require("lean").setup yourself with your own options.
- Key mappings use <LocalLeader> (default \\): \\i toggles the infoview.
- See: https://github.com/Julian/lean.nvim
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

VERSION="v2026.4.1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; VERSION="${1:?--version needs a value}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v nvim >/dev/null 2>&1; then
  echo "❌ Neovim not found. Select the neovim template (or run neovim--setup.sh first)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git ca-certificates
rm -rf /var/lib/apt/lists/*

# Neovim reads /usr/local/share/nvim/site through XDG_DATA_DIRS; pack/*/start loads at startup.
SITE=/usr/local/share/nvim/site
DEST="$SITE/pack/booth-lean/start/lean.nvim"
echo "⬇️  Installing lean.nvim ${VERSION} ..."
rm -rf "$DEST"
git clone --quiet --depth 1 --branch "$VERSION" https://github.com/Julian/lean.nvim "$DEST"
rm -rf "$DEST/.git"

mkdir -p "$SITE/plugin"
cat > "$SITE/plugin/booth-lean.lua" <<'EOF'
-- lean.nvim, set up by CodingBooth (lean-nvim--setup.sh). Runs after the user's init.lua;
-- set vim.g.booth_lean = false there to skip it, e.g. to call require("lean").setup yourself.
if vim.g.booth_lean == false then
  return
end
require("lean").setup { mappings = true }
EOF
chmod -R a+rX "$SITE"

# Loads, sets up, and knows .lean files.
nvim --headless -c 'lua assert(require("lean"))' -c 'qa!'

echo "✅ lean.nvim installed."
echo "   lean.nvim → ${VERSION} (${DEST})"

cat <<'EON'
ℹ️ Ready to use (in a Lean project):
- Open a file:   nvim MyFile.lean      (the language server starts by itself)
- Infoview:      \i toggles it; it follows the cursor
- Unicode:       type \forall, \to, \N, \le ... then a space
- Commands:      :LeanGoal  :LeanInfoviewToggle  :LeanRestartFile
- Manual:        https://github.com/Julian/lean.nvim/wiki/The-lean.nvim-Manual
EON
