#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# xfce-theme--setup.sh — modern default look for XFCE: Greybird-dark for both
# the window decorations (xfwm4) and the GTK app theme, Adwaita icons.
#
# Only the *system* defaults under /etc/xdg are changed. xfconf consults them
# solely for properties the user has never set, so a theme picked later from
# Settings → Appearance / Window Manager lands in ~/.config and always wins —
# no autostart enforcer needed (unlike the wallpaper, xfsettingsd and xfwm4 do
# not write their own fallback into the user's channel on first login).
#
# Usage: xfce-theme--setup.sh
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v xfce4-session &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "XFCE not installed (run xfce--setup.sh first)"
fi

GTK_THEME="Greybird-dark"
WM_THEME="Greybird-dark"
ICON_THEME="Adwaita"

# Both usually arrive with xfce4 already; named here so the look never depends
# on a recommends chain that a future xfce4 package might drop.
apt--install.sh greybird-gtk-theme adwaita-icon-theme

for d in "/usr/share/themes/${GTK_THEME}/gtk-3.0" "/usr/share/themes/${WM_THEME}/xfwm4" "/usr/share/icons/${ICON_THEME}"; do
  if [[ ! -d "$d" ]]; then
    echo "❌ Expected theme directory missing: $d" >&2
    exit 2
  fi
done

XFCONF_DIR="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
XSETTINGS_XML="${XFCONF_DIR}/xsettings.xml"
XFWM4_XML="${XFCONF_DIR}/xfwm4.xml"
mkdir -p "$XFCONF_DIR"

# ---- GTK + icon theme (xsettings channel) ----
# xfce4-settings ships this file with the full Net/Gtk/Xft tree; only the two
# values change, so edit in place rather than replacing the whole channel.
if [[ ! -f "$XSETTINGS_XML" ]]; then
  echo "❌ ${XSETTINGS_XML} not found (is xfce4-settings installed?)" >&2
  exit 2
fi
sed -i -E \
  -e "s|(<property name=\"ThemeName\" type=\"string\" value=\")[^\"]*\"|\1${GTK_THEME}\"|" \
  -e "s|(<property name=\"IconThemeName\" type=\"string\" value=\")[^\"]*\"|\1${ICON_THEME}\"|" \
  "$XSETTINGS_XML"
grep -q "name=\"ThemeName\" type=\"string\" value=\"${GTK_THEME}\"" "$XSETTINGS_XML"
grep -q "name=\"IconThemeName\" type=\"string\" value=\"${ICON_THEME}\"" "$XSETTINGS_XML"

# ---- Window decorations (xfwm4 channel) ----
# No package ships a system xfwm4.xml; xfwm4 otherwise falls back to
# /usr/share/xfwm4/defaults (theme=Default). Compositing is already on there,
# and stated here too because Plank's shadows and transparency depend on it.
cat > "$XFWM4_XML" <<XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="${WM_THEME}"/>
    <property name="use_compositing" type="bool" value="true"/>
  </property>
</channel>
XMLEOF
chmod 0644 "$XFWM4_XML"

echo "✅ XFCE theme defaults: GTK=${GTK_THEME}, window=${WM_THEME}, icons=${ICON_THEME}"
echo "   ${XSETTINGS_XML}"
echo "   ${XFWM4_XML}"
