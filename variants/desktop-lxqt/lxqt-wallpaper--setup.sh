#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# lxqt-wallpaper--setup.sh — set a custom wallpaper as the LXQt default
# Writes system-level pcmanfm-qt settings so the wallpaper applies on first login.
# LXQt draws its desktop (and wallpaper) with pcmanfm-qt under the "lxqt" profile.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

WALLPAPER="${1:-/usr/share/backgrounds/codingbooth/wallpaper.png}"

if [[ ! -f "$WALLPAPER" ]]; then
  echo "❌ Wallpaper not found: $WALLPAPER" >&2
  exit 2
fi

# pcmanfm-qt uses /etc/xdg/ as the system-level default; the user-level config
# (~/.config/pcmanfm-qt/lxqt/settings.conf) overrides it. On first boot (no user
# config) this system default is used. The profile name for LXQt is "lxqt".
PCMANFM_DIR="/etc/xdg/pcmanfm-qt/lxqt"
SETTINGS="${PCMANFM_DIR}/settings.conf"

mkdir -p "$PCMANFM_DIR"

# WallpaperMode options: color | stretch | fit | center | tile | zoom
cat > "$SETTINGS" <<EOF
[Desktop]
Wallpaper=${WALLPAPER}
WallpaperMode=stretch
BgColor=#000000
ShowWmMenu=false
EOF

chmod 644 "$SETTINGS"

# Ensure pcmanfm-qt draws the desktop on session start (it is the LXQt default,
# but make it explicit so the wallpaper is honored even on minimal installs).
install -d /etc/xdg/autostart
cat > /etc/xdg/autostart/lxqt-wallpaper.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=CodingBooth Desktop (pcmanfm-qt)
Exec=pcmanfm-qt --desktop --profile=lxqt
OnlyShowIn=LXQt;
X-LXQt-Need-Tray=false
DESK

echo "✅ LXQt wallpaper configured: ${WALLPAPER}"
echo "   Config: ${SETTINGS}"
