#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Installs TeXstudio, a desktop LaTeX editor with a built-in PDF viewer, from
# Ubuntu's packages, and puts its icon on the desktop.
#
# TeXstudio is only the editor: it compiles with whatever TeX is in the image,
# so pair it with `setup latex` (the latex+texstudio extension does).
# Installed with --no-install-recommends, so it does not drag in a TeX Live of
# its own and the latex setup's --scheme stays the one in charge.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Requires a desktop variant (desktop-xfce, desktop-kde, desktop-lxqt, desktop-wayland)
- Installs TeXstudio from Ubuntu's archive (4.9 on 26.04), frozen by APT_SNAPSHOT when set
- Creates a desktop shortcut
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
esac

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

echo "📦 Installing TeXstudio ..."
apt--install.sh texstudio

# ---- desktop shortcut ----
cb-desktop-icon.sh texstudio.desktop

# ---- friendly summary ----
echo "✅ TeXstudio installed."
echo -n "   texstudio → "; dpkg-query -W -f='${Version}\n' texstudio 2>/dev/null || echo "(not found)"

cat <<'EON'
ℹ️ Ready to use:
- Double-click the TeXstudio icon on the desktop, or run: texstudio main.tex &
- F5 builds and shows the PDF; F6 builds only.

Notes:
- TeXstudio compiles with the TeX in the image — select latex alongside it.
- F5 runs BibTeX on its own when the document has a bibliography.
EON
