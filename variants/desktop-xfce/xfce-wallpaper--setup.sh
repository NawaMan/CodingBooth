#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# xfce-wallpaper--setup.sh — set a custom wallpaper as the XFCE default
# Writes system-level xfconf XML so the wallpaper applies on first login.
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

# XFCE uses /etc/xdg/ as the system-level default for xfconf settings.
# User-level config (~/.config/xfce4/xfconf/...) overrides this.
# On first boot (no user config), this system default is used.
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

echo "✅ XFCE wallpaper configured: ${WALLPAPER}"
echo "   Config: ${DESKTOP_XML}"
