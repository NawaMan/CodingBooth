#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Installs Thonny, a beginner-friendly Python IDE
- Requires a desktop environment
- Requires Python (installed via the python template)
- Installs via apt (Debian/Ubuntu thonny package)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

# ---- install Thonny ----
export DEBIAN_FRONTEND=noninteractive
echo "• Installing Thonny from apt ..."
# python3-tk: File → Open uses Tk dialogs when zenity is off (see config below).
apt-get update
apt-get install -y --no-install-recommends thonny python3-tk
rm -rf /var/lib/apt/lists/*

# File → Open on apt Thonny 4.0.1 calls zenity when file.avoid_zenity is
# unset/False. Zenity over noVNC exits 255 ("This option is not available"),
# so the Open icon does nothing. Force Tk dialogs on every launch.
THONNY_INI_BODY='[file]
avoid_zenity = True
use_zenity = False
last_browser_folder = /home/coder/code

[run]
working_directory = /home/coder/code
'
mkdir -p /etc/skel/.config/Thonny
printf '%s' "$THONNY_INI_BODY" > /etc/skel/.config/Thonny/configuration.ini
chmod 0644 /etc/skel/.config/Thonny/configuration.ini

# Wrapper ahead of /usr/bin/thonny: rewrite the user's ini, then exec apt Thonny.
# A one-shot startup is not enough — Thonny 4.0.1 writes its own config on first
# run with avoid_zenity=False, which would undo a seed.
WRAPPER="/usr/local/bin/thonny"
cat > "$WRAPPER" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from configparser import ConfigParser
from pathlib import Path
p = Path.home() / ".config/Thonny/configuration.ini"
p.parent.mkdir(parents=True, exist_ok=True)
cp = ConfigParser(interpolation=None)
if p.exists():
    cp.read(p, encoding="utf-8")
if not cp.has_section("file"):
    cp.add_section("file")
cp.set("file", "avoid_zenity", "True")
cp.set("file", "use_zenity", "False")
cp.set("file", "last_browser_folder", "/home/coder/code")
if not cp.has_section("run"):
    cp.add_section("run")
cp.set("run", "working_directory", "/home/coder/code")
with p.open("w", encoding="utf-8") as f:
    cp.write(f)
PY
exec /usr/bin/thonny "$@"
WRAPPER
chmod 755 "$WRAPPER"

# ---- summary ----
echo ""
# Register a Thonny desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh thonny
# The packaged launcher often Exec=/usr/bin/thonny, which would skip the wrapper.
for desk in /usr/share/applications/thonny.desktop \
            /usr/share/applications/org.thonny.Thonny.desktop \
            /etc/skel/Desktop/thonny.desktop \
            /etc/skel/Desktop/org.thonny.Thonny.desktop; do
  if [ -f "$desk" ]; then
    sed -i 's|^Exec=.*thonny|Exec=/usr/local/bin/thonny|' "$desk" || true
  fi
done
echo "✅ Thonny installed."
echo -n "   thonny → "; thonny --version 2>/dev/null || true
echo ""
echo "ℹ️  Launch: thonny"
echo "   File → Open uses Tk dialogs (zenity is disabled; it no-ops over VNC)."
echo "   Working directory: /home/coder/code"
echo "   Docs:   https://thonny.org/"
