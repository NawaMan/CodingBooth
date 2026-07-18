#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# xfce-wallpaper--setup.sh — set the CodingBooth wallpaper as the XFCE default.
#
# Two layers, because a single one is not enough:
#   1. A system-level xfconf XML default (/etc/xdg/...). This is the "seed" XFCE
#      copies into a fresh user profile.
#   2. An XFCE autostart entry that re-applies the wallpaper via xfconf-query
#      once the session is up.
#
# Layer 2 is required: on first login xfdesktop enumerates the (VNC) monitor and
# writes its OWN compiled-in fallback backdrop (xfce-blue.jpg) into the user's
# ~/.config/xfce4/.../xfce4-desktop.xml, which then overrides the system default.
# The autostart script runs after xfdesktop has done that, so its xfconf writes
# win — and xfdesktop live-applies them. This mirrors how the KDE/LXQt variants
# enforce their wallpaper.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

WALLPAPER="${1:-/usr/share/backgrounds/codingbooth/wallpaper.jpg}"

if [[ ! -f "$WALLPAPER" ]]; then
  echo "❌ Wallpaper not found: $WALLPAPER" >&2
  exit 2
fi

# --------------------------------------------------------------------------
# Layer 1 — system-level xfconf default
# XFCE uses /etc/xdg/ as the system-level default for xfconf settings.
# User-level config (~/.config/xfce4/xfconf/...) overrides this.
# --------------------------------------------------------------------------
XFCONF_DIR="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
DESKTOP_XML="${XFCONF_DIR}/xfce4-desktop.xml"

mkdir -p "$XFCONF_DIR"

# The monitor name is VNC-0 for TigerVNC sessions.
# Set wallpaper for workspaces 0-3 (XFCE default is 4 workspaces).
cat > "$DESKTOP_XML" <<XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVNC-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="${WALLPAPER}"/>
        </property>
        <property name="workspace1" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="${WALLPAPER}"/>
        </property>
        <property name="workspace2" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="${WALLPAPER}"/>
        </property>
        <property name="workspace3" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="${WALLPAPER}"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XMLEOF

chmod 644 "$DESKTOP_XML"

# --------------------------------------------------------------------------
# Layer 2 — per-session enforcement via xfconf-query
# Runs inside the XFCE session (DISPLAY/DBUS/XAUTHORITY already exported by
# xfce4-session) once xfdesktop is up, and overwrites whatever backdrop image
# xfdesktop chose with the CodingBooth wallpaper.
# --------------------------------------------------------------------------
ENFORCE_BIN="/usr/local/bin/xfce-set-wallpaper"

install -m 0755 /dev/null "$ENFORCE_BIN"
cat > "$ENFORCE_BIN" <<SETSH
#!/usr/bin/env bash
# xfce-set-wallpaper — force the CodingBooth wallpaper for the current XFCE
# session. Installed by xfce-wallpaper--setup.sh; launched from XFCE autostart.
set -uo pipefail

WALLPAPER="${WALLPAPER}"
[[ -f "\$WALLPAPER" ]] || exit 0

# Wait until xfdesktop is running AND has populated its backdrop properties.
# Once the last-image nodes exist, xfdesktop has already written its own
# default, so our overwrite below is the final word.
for _ in \$(seq 1 60); do
  if pgrep -x xfdesktop >/dev/null 2>&1 &&
     xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -q '/last-image\$'; then
    break
  fi
  sleep 1
done

# Collect every backdrop last-image property xfdesktop created. Fall back to
# building paths from the connected monitors if none were found (rare race).
mapfile -t props < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image\$' || true)
if [[ \${#props[@]} -eq 0 ]]; then
  monitors=\$(xrandr --query 2>/dev/null | awk '/ connected/{print \$1}')
  [[ -n "\$monitors" ]] || monitors="VNC-0"
  for m in \$monitors; do
    for ws in 0 1 2 3; do
      props+=("/backdrop/screen0/monitor\${m}/workspace\${ws}/last-image")
    done
  done
fi

for p in "\${props[@]}"; do
  base="\${p%/last-image}"
  # image-style 5 = scaled (keep aspect); color-style 0 = solid color fill
  xfconf-query -c xfce4-desktop -p "\$base/image-style" -n -t int -s 5 2>/dev/null ||
    xfconf-query -c xfce4-desktop -p "\$base/image-style" -s 5 2>/dev/null || true
  xfconf-query -c xfce4-desktop -p "\$p" -n -t string -s "\$WALLPAPER" 2>/dev/null ||
    xfconf-query -c xfce4-desktop -p "\$p" -s "\$WALLPAPER" 2>/dev/null || true
done

# Ask xfdesktop to repaint (harmless if it already picked up the xfconf change).
xfdesktop --reload 2>/dev/null || true

echo "✅ xfce-set-wallpaper: applied \$WALLPAPER to \${#props[@]} backdrop(s)"
SETSH

# ---- Autostart entry (XFCE only) ----
install -d /etc/xdg/autostart
cat > /etc/xdg/autostart/xfce-set-wallpaper.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Set CodingBooth Wallpaper
Exec=/usr/local/bin/xfce-set-wallpaper
OnlyShowIn=XFCE;
DESK

echo "✅ XFCE wallpaper configured: ${WALLPAPER}"
echo "   System default: ${DESKTOP_XML}"
echo "   Enforcer:       ${ENFORCE_BIN}"
echo "   Autostart:      /etc/xdg/autostart/xfce-set-wallpaper.desktop"
