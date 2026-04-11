#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# kde-wallpaper--setup.sh — set a custom wallpaper as the KDE Plasma default
# Creates an autostart script that applies the wallpaper on first login via
# plasmashell's scripting API, then disables itself.
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

# ---- Helper script: runs once on first KDE login ----
install -m 0755 /dev/null /usr/local/bin/kde-set-wallpaper
cat > /usr/local/bin/kde-set-wallpaper <<SETSH
#!/usr/bin/env bash
set -euo pipefail

WALLPAPER="${WALLPAPER}"

# Wait for plasmashell to be ready (it needs to be running for qdbus to work)
for i in {1..60}; do
  if qdbus org.kde.plasmashell /PlasmaShell 2>/dev/null | grep -q evaluateScript; then
    break
  fi
  sleep 1
done

if ! qdbus org.kde.plasmashell /PlasmaShell 2>/dev/null | grep -q evaluateScript; then
  echo "⚠️ kde-set-wallpaper: plasmashell not ready after 60s, skipping" >&2
  exit 0
fi

# Use plasmashell's scripting API to set wallpaper on all desktops
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var allDesktops = desktops();
for (var i = 0; i < allDesktops.length; i++) {
    var d = allDesktops[i];
    d.wallpaperPlugin = 'org.kde.image';
    d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
    d.writeConfig('Image', 'file://\${WALLPAPER}');
}
" 2>/dev/null || echo "⚠️ kde-set-wallpaper: evaluateScript failed" >&2

# Disable autostart so this only runs once
AUTOSTART="\${HOME}/.config/autostart/kde-set-wallpaper.desktop"
mkdir -p "\$(dirname "\$AUTOSTART")"
if [[ -f "\$AUTOSTART" ]]; then
  sed -i 's/^Hidden=.*/Hidden=true/; t; \$aHidden=true' "\$AUTOSTART" || true
else
  cat > "\$AUTOSTART" <<'DESK'
[Desktop Entry]
Type=Application
Name=Set CodingBooth Wallpaper
Exec=/usr/local/bin/kde-set-wallpaper
OnlyShowIn=KDE;
Hidden=true
DESK
fi

echo "✅ KDE wallpaper set to: \$WALLPAPER"
SETSH

# ---- Autostart entry ----
install -d /etc/xdg/autostart
cat > /etc/xdg/autostart/kde-set-wallpaper.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Set CodingBooth Wallpaper
Exec=/usr/local/bin/kde-set-wallpaper
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
Hidden=false
DESK

echo "✅ KDE wallpaper autostart configured: ${WALLPAPER}"
echo "   Script:    /usr/local/bin/kde-set-wallpaper"
echo "   Autostart: /etc/xdg/autostart/kde-set-wallpaper.desktop"
