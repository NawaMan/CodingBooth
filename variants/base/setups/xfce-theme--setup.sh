#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# xfce-theme--setup.sh — the default look of the XFCE booth, in one place:
#
#   app style (GTK)      Greybird-dark     greybird-gtk-theme (apt)
#   window borders       Greybird-dark     greybird-gtk-theme (apt)
#   icons                Reversal-dark     reversal-icons--setup.sh
#   cursor               gruppled_white    gruppled-cursors--setup.sh
#   cursor size          40                (the only size Gruppled ships)
#
# The theme packs only install; this is the one script that picks defaults, so
# run it after them. More themes are opt-in templates (tela-icons, orchis-gtk,
# material-cursors); switch with `booth--theme set <type> <name>` or in Settings.
#
# Only the *system* defaults are changed (/etc/xdg xfconf, the x-cursor-theme
# alternative). xfconf consults them solely for properties the user has never
# set, so a choice made later in Settings, or with booth--theme, always wins —
# no autostart enforcer needed (xfsettingsd and xfwm4 do not write their own
# fallback into the user's channel on first login, unlike xfdesktop's wallpaper).
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
ICON_THEME="Reversal-dark"
CURSOR_THEME="gruppled_white"
CURSOR_SIZE=40

# Greybird usually arrives with xfce4 already; named here so the look never
# depends on a recommends chain that a future xfce4 package might drop.
apt--install.sh greybird-gtk-theme adwaita-icon-theme

missing=()
for d in "/usr/share/themes/${GTK_THEME}/gtk-3.0"  \
         "/usr/share/themes/${WM_THEME}/xfwm4"     \
         "/usr/share/icons/${ICON_THEME}"          \
         "/usr/share/icons/${CURSOR_THEME}/cursors"; do
  [[ -d "$d" ]] || missing+=("$d")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Theme directories missing — run the theme packs first" >&2
  echo "   (reversal-icons, gruppled-cursors):" >&2
  printf '     %s\n' "${missing[@]}" >&2
  exit 2
fi

XFCONF_DIR="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
XSETTINGS_XML="${XFCONF_DIR}/xsettings.xml"
XFWM4_XML="${XFCONF_DIR}/xfwm4.xml"
mkdir -p "$XFCONF_DIR"

# ---- GTK, icon and cursor theme (xsettings channel) ----
# xfce4-settings ships this file with the full Net/Gtk/Xft tree; only these
# values change, so edit in place rather than replacing the whole channel.
if [[ ! -f "$XSETTINGS_XML" ]]; then
  echo "❌ ${XSETTINGS_XML} not found (is xfce4-settings installed?)" >&2
  exit 2
fi
set_xsetting() {
  local name="$1" type="$2" value="$3"
  sed -i -E "s|(<property name=\"${name}\" type=\"${type}\" value=\")[^\"]*\"|\1${value}\"|" "$XSETTINGS_XML"
  if ! grep -q "name=\"${name}\" type=\"${type}\" value=\"${value}\"" "$XSETTINGS_XML"; then
    echo "❌ Could not set ${name}=${value} in ${XSETTINGS_XML}" >&2
    exit 2
  fi
}
set_xsetting ThemeName       string "$GTK_THEME"
set_xsetting IconThemeName   string "$ICON_THEME"
set_xsetting CursorThemeName string "$CURSOR_THEME"
set_xsetting CursorThemeSize int    "$CURSOR_SIZE"

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

# ---- Cursor for non-GTK X clients (the root window, xterm, …) ----
# They read /usr/share/icons/default/index.theme, the x-cursor-theme
# alternative. Gruppled ships no cursor.theme to point it at, so add one.
CURSOR_ALT="/usr/share/icons/${CURSOR_THEME}/cursor.theme"
if [[ ! -f "$CURSOR_ALT" ]]; then
  printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_THEME" > "$CURSOR_ALT"
  chmod 0644 "$CURSOR_ALT"
fi
update-alternatives --install /usr/share/icons/default/index.theme x-cursor-theme "$CURSOR_ALT" 100
update-alternatives --set x-cursor-theme "$CURSOR_ALT"

echo "✅ XFCE theme defaults: GTK=${GTK_THEME}, window=${WM_THEME}, icons=${ICON_THEME}, cursor=${CURSOR_THEME} (${CURSOR_SIZE})"
echo "   ${XSETTINGS_XML}"
echo "   ${XFWM4_XML}"
