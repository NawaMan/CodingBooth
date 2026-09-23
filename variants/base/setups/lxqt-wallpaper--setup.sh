#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# lxqt-wallpaper--setup.sh — set the CodingBooth wallpaper as the LXQt default.
# LXQt draws its desktop (and wallpaper) with pcmanfm-qt under the "lxqt" profile.
#
# Two layers, matching the XFCE/KDE variants:
#   1. A system-level pcmanfm-qt settings default (/etc/xdg/...) used on a fresh
#      profile.
#   2. An autostart enforcer that re-applies the wallpaper via
#      `pcmanfm-qt --set-wallpaper` once the desktop daemon is up, so a user-level
#      config written by pcmanfm-qt cannot leave a blank/other background.
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

# --------------------------------------------------------------------------
# Layer 1 — system-level pcmanfm-qt default
# The user-level config (~/.config/pcmanfm-qt/lxqt/settings.conf) overrides it.
# On first boot (no user config) this system default is used. Profile = "lxqt".
# --------------------------------------------------------------------------
PCMANFM_DIR="/etc/xdg/pcmanfm-qt/lxqt"
SETTINGS="${PCMANFM_DIR}/settings.conf"

mkdir -p "$PCMANFM_DIR"

# WallpaperMode options: color | stretch | fit | center | tile | zoom
# zoom = "Zoom the image to fill the entire screen" (keeps aspect ratio, crops overflow)
cat > "$SETTINGS" <<EOF
[Desktop]
Wallpaper=${WALLPAPER}
WallpaperMode=zoom
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

# --------------------------------------------------------------------------
# Layer 2 — per-session enforcement via pcmanfm-qt --set-wallpaper
# --------------------------------------------------------------------------
ENFORCE_BIN="/usr/local/bin/lxqt-set-wallpaper"

install -m 0755 /dev/null "$ENFORCE_BIN"
cat > "$ENFORCE_BIN" <<SETSH
#!/usr/bin/env bash
# lxqt-set-wallpaper — force the CodingBooth wallpaper for the current LXQt
# session. Installed by lxqt-wallpaper--setup.sh; launched from LXQt autostart.
set -uo pipefail

WALLPAPER="${WALLPAPER}"
[[ -f "\$WALLPAPER" ]] || exit 0

# Wait for the pcmanfm-qt desktop daemon to be running.
for _ in \$(seq 1 60); do
  pgrep -x pcmanfm-qt >/dev/null 2>&1 && break
  sleep 1
done
if ! pgrep -x pcmanfm-qt >/dev/null 2>&1; then
  echo "⚠️ lxqt-set-wallpaper: pcmanfm-qt not running after 60s, skipping" >&2
  exit 0
fi
sleep 1

if pcmanfm-qt --profile=lxqt --set-wallpaper="\$WALLPAPER" --wallpaper-mode=zoom 2>/dev/null; then
  echo "✅ lxqt-set-wallpaper: applied \$WALLPAPER"
else
  echo "⚠️ lxqt-set-wallpaper: pcmanfm-qt --set-wallpaper failed" >&2
fi
exit 0
SETSH

cat > /etc/xdg/autostart/lxqt-set-wallpaper.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Set CodingBooth Wallpaper
Exec=/usr/local/bin/lxqt-set-wallpaper
OnlyShowIn=LXQt;
X-LXQt-Need-Tray=false
DESK

echo "✅ LXQt wallpaper configured: ${WALLPAPER}"
echo "   System default: ${SETTINGS}"
echo "   Enforcer:       ${ENFORCE_BIN}"
echo "   Autostart:      /etc/xdg/autostart/lxqt-set-wallpaper.desktop"
