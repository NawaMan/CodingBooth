#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--clangd--setup.sh — Install clangd, the C/C++ language server, from Ubuntu.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Installs Ubuntu's clangd package through apt--install.sh (so APT_SNAPSHOT applies)
- Skips when clangd is already on PATH: the clang template installs its own
- Works beside gcc: clangd reads compile_commands.json, whichever compiler wrote it
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
esac

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

if command -v clangd >/dev/null 2>&1; then
  echo "ℹ️  clangd is already installed: $(command -v clangd)"
else
  # Through apt--install.sh, so the booth's APT_SNAPSHOT freezes it like any apt package.
  apt--install.sh clangd
fi

echo "✅ clangd installed."
echo -n "   clangd → "; clangd --version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: clangd
- Fresh, Helix, and neovim+lsp pick it up for C and C++ files

Notes:
- clangd needs to know how files are compiled: a compile_commands.json at the project root
  (cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON, or bear -- make), or a compile_flags.txt.
- See: https://clangd.llvm.org
EON
