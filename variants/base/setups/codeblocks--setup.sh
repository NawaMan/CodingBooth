#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Requires a desktop variant (desktop-xfce, desktop-kde, ...)
- Installs Code::Blocks from Ubuntu's packages, with the contrib plugins
- Adds gdb (the debugger Code::Blocks drives) and xterm (the console it runs programs in)
- Compilers come from their own setups: gcc (C/C++), gcc+fortran (Fortran)
- The wxSmith GUI-designer plugins are parked in /usr/lib/codeblocks/plugins-disabled:
  with Ubuntu 26.04's gdk-pixbuf they hang Code::Blocks on its splash screen
- Creates a desktop shortcut
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- install ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
echo "📦 Installing Code::Blocks ..."
apt-get install -y --no-install-recommends codeblocks codeblocks-contrib gdb xterm
rm -rf /var/lib/apt/lists/*

# Code::Blocks 25.03 hangs on its splash screen with gdk-pixbuf 2.44 (Ubuntu 26.04), whose
# glycin image loader never answers wxSmith's startup image loads. Park the wxSmith plugins
# (the wxWidgets GUI designer) where Code::Blocks does not look; move them back to retry.
PLUGIN_DIR=/usr/lib/codeblocks/plugins
mkdir -p "${PLUGIN_DIR}-disabled"
for so in "$PLUGIN_DIR"/libwxsmith*.so "$PLUGIN_DIR"/libwxSmith*.so; do
  [[ -e "$so" ]] && mv "$so" "${PLUGIN_DIR}-disabled/"
done

# Code::Blocks only auto-detects GCC at /usr/bin/gcc. The gcc setup installs gcc-<N> and puts
# gcc/g++ in /usr/local/bin, so point /usr/bin at those when nothing else is there — that keeps
# the GCC_VERSION the booth chose.
for t in gcc g++; do
  if [[ ! -e /usr/bin/$t && -x /usr/local/bin/$t ]]; then
    ln -s /usr/local/bin/$t /usr/bin/$t
  fi
done

cb-desktop-icon.sh codeblocks.desktop

# ---- summary ----
echo "✅ Code::Blocks installed."
echo -n "   version → "; dpkg-query -W -f='${Version}\n' codeblocks || true

cat <<'EON'
ℹ️ Ready to use:
- codeblocks                 # or the desktop icon
- File > New > Project...    # Console application (C/C++) or Fortran application
EON
