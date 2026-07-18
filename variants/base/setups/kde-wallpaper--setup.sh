#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# kde-wallpaper--setup.sh — set the CodingBooth wallpaper as the KDE Plasma default.
# Installs a setter script that, once plasmashell is up, applies the wallpaper via
# the dedicated plasma-apply-wallpaperimage CLI (falling back to plasmashell's
# scripting API over qdbus). Wired from both start-kde and an autostart entry.
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

# ---- Helper script: runs once plasmashell is ready ----
install -m 0755 /dev/null /usr/local/bin/kde-set-wallpaper
cat > /usr/local/bin/kde-set-wallpaper <<SETSH
#!/usr/bin/env bash
# kde-set-wallpaper — force the CodingBooth wallpaper for the current Plasma
# session. Installed by kde-wallpaper--setup.sh; launched from start-kde and
# from KDE autostart.
set -uo pipefail

WALLPAPER="${WALLPAPER}"
[[ -f "\$WALLPAPER" ]] || exit 0

# Wait for plasmashell to actually be running (tool-agnostic readiness check).
for _ in \$(seq 1 60); do
  pgrep -x plasmashell >/dev/null 2>&1 && break
  sleep 1
done
if ! pgrep -x plasmashell >/dev/null 2>&1; then
  echo "⚠️ kde-set-wallpaper: plasmashell not running after 60s, skipping" >&2
  exit 0
fi
# Give D-Bus a moment to register the shell's scripting interface.
sleep 2

# 1) Preferred: the dedicated CLI shipped with plasma-workspace (Plasma 5.18+).
if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
  if plasma-apply-wallpaperimage "\$WALLPAPER" 2>/dev/null; then
    echo "✅ kde-set-wallpaper: applied \$WALLPAPER via plasma-apply-wallpaperimage"
    exit 0
  fi
fi

# 2) Fallback: drive plasmashell's scripting API over qdbus (name varies by Qt).
QDBUS="\$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus-qt5 || command -v qdbus || true)"
if [[ -n "\$QDBUS" ]]; then
  "\$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var allDesktops = desktops();
for (var i = 0; i < allDesktops.length; i++) {
    var d = allDesktops[i];
    d.wallpaperPlugin = 'org.kde.image';
    d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
    d.writeConfig('Image', 'file://\${WALLPAPER}');
}
" 2>/dev/null && { echo "✅ kde-set-wallpaper: applied \$WALLPAPER via qdbus"; exit 0; }
fi

echo "⚠️ kde-set-wallpaper: no working method to set wallpaper" >&2
exit 0
SETSH

# ---- Autostart entry (KDE only), late phase so plasmashell exists ----
install -d /etc/xdg/autostart
cat > /etc/xdg/autostart/kde-set-wallpaper.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Set CodingBooth Wallpaper
Exec=/usr/local/bin/kde-set-wallpaper
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
DESK

echo "✅ KDE wallpaper autostart configured: ${WALLPAPER}"
echo "   Script:    /usr/local/bin/kde-set-wallpaper"
echo "   Autostart: /etc/xdg/autostart/kde-set-wallpaper.desktop"
