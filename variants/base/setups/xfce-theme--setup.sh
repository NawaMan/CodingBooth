#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.3.0

# xfce-theme--setup.sh — the default look of the XFCE booth, in one place:
#
#   app style (GTK)      Greybird-dark     greybird-gtk-theme (apt)
#   window borders       Greybird-dark-wide: Greybird-dark-accessibility with its
#                        edges widened to --border px (default 6, easy to grab)
#   icons                Reversal-dark     reversal-icons--setup.sh
#   cursor               gruppled_white    gruppled-cursors--setup.sh
#   cursor size          40                (Gruppled's own size; 24 and 30 are added by
#                                           gruppled-cursors--setup.sh for a smaller cursor)
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
# Usage: xfce-theme--setup.sh [--border N]
#   --border N   window edge width in px, 3..16 (default 6). 3 uses
#                Greybird-dark-accessibility as it ships.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

BORDER=6
while [[ $# -gt 0 ]]; do
  case "$1" in
    --border) BORDER="${2:-}"; shift 2 ;;
    *) echo "❌ Unknown arg: $1 (usage: xfce-theme--setup.sh [--border N])" >&2; exit 1 ;;
  esac
done
if ! [[ "$BORDER" =~ ^[0-9]+$ ]] || (( BORDER < 3 || BORDER > 16 )); then
  echo "❌ --border must be a number of px from 3 to 16, got '${BORDER}'" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v xfce4-session &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "XFCE not installed (run xfce--setup.sh first)"
fi

GTK_THEME="Greybird-dark"
# Same look as Greybird-dark, but with 3 px window edges instead of 1 px; ships
# in the same greybird-gtk-theme package. xfwm4 only resizes from the border the
# theme draws (no invisible grab margin, unlike KDE/GNOME), so the edge width is
# the grab width. Greybird-dark-wide below widens it further.
BASE_WM_THEME="Greybird-dark-accessibility"
WM_THEME="$BASE_WM_THEME"
(( BORDER > 3 )) && WM_THEME="Greybird-dark-wide"
ICON_THEME="Reversal-dark"
CURSOR_THEME="gruppled_white"
CURSOR_SIZE=40

# Greybird usually arrives with xfce4 already; named here so the look never
# depends on a recommends chain that a future xfce4 package might drop.
apt--install.sh greybird-gtk-theme adwaita-icon-theme

missing=()
for d in "/usr/share/themes/${GTK_THEME}/gtk-3.0"  \
         "/usr/share/themes/${BASE_WM_THEME}/xfwm4" \
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

# ---- Greybird-dark-wide: the accessibility theme with N px edges ----
# Its edge pieces are XPM text: left/right are 3 columns (outer line, dark
# middle, inner line), bottom the same 3 rows, the corners follow suit. Widen
# by repeating the middle column/row, so the look stays and only the width
# grows. Rebuilt on every run, so a new --border always applies.
widen_xpm() {   # <in> <out> <col: left|right|none> <dup-row: 0|1> <extra>
  awk -v side="$3" -v duprow="$4" -v k="$5" '
    function rep(s, n,   r) { r = ""; while (n-- > 0) r = r s; return r }
    /^"/ && !hdr { hdr = 1; match($0, /^"[^"]*"/); split(substr($0, 2, RLENGTH - 2), h, " ")
                   nc = h[3]
                   h[1] += (side != "none" ? k : 0); h[2] += (duprow ? k : 0)
                   print "\"" h[1] " " h[2] " " h[3] " " h[4] "\"" substr($0, RLENGTH + 1); next }
    /^"/ && hdr && nc > 0 { nc--; print; next }
    /^"/ && hdr { row++
                  match($0, /^"[^"]*"/); px = substr($0, 2, RLENGTH - 2); tail = substr($0, RLENGTH + 1)
                  # The first rows of a top corner are its rounded curve (outer pixel
                  # transparent): widen those at the title end so the curve keeps
                  # its shape.
                  n = length(px)
                  if (side == "left")  c = (substr(px, 1, 1) == " ") ? n : 2
                  if (side == "right") c = (substr(px, n, 1) == " ") ? 1 : n - 1
                  if (side == "none")  c = 0
                  if (side == "right" && c == 1) { px = rep(substr(px, 1, 1), k) px; c = 0 }
                  if (c) px = substr(px, 1, c) rep(substr(px, c, 1), k) substr(px, c + 1)
                  print "\"" px "\"" tail
                  if (duprow && row == 2) for (i = 0; i < k; i++) print "\"" px "\","
                  next }
    { print }' "$1" > "$2"
}
if [[ "$WM_THEME" == "Greybird-dark-wide" ]]; then
  SRC="/usr/share/themes/${BASE_WM_THEME}"
  DST="/usr/share/themes/${WM_THEME}"
  EXTRA=$(( BORDER - 3 ))
  rm -rf "$DST"
  mkdir -p "$DST"
  cp -a "$SRC/xfwm4" "$DST/xfwm4"
  for state in active inactive; do
    widen_xpm "$SRC/xfwm4/left-$state.xpm"         "$DST/xfwm4/left-$state.xpm"         left  0 "$EXTRA"
    widen_xpm "$SRC/xfwm4/right-$state.xpm"        "$DST/xfwm4/right-$state.xpm"        right 0 "$EXTRA"
    widen_xpm "$SRC/xfwm4/top-left-$state.xpm"     "$DST/xfwm4/top-left-$state.xpm"     left  0 "$EXTRA"
    widen_xpm "$SRC/xfwm4/top-right-$state.xpm"    "$DST/xfwm4/top-right-$state.xpm"    right 0 "$EXTRA"
    widen_xpm "$SRC/xfwm4/bottom-$state.xpm"       "$DST/xfwm4/bottom-$state.xpm"       none  1 "$EXTRA"
    widen_xpm "$SRC/xfwm4/bottom-left-$state.xpm"  "$DST/xfwm4/bottom-left-$state.xpm"  left  1 "$EXTRA"
    widen_xpm "$SRC/xfwm4/bottom-right-$state.xpm" "$DST/xfwm4/bottom-right-$state.xpm" right 1 "$EXTRA"
  done
  chmod -R a+rX "$DST"
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

echo "✅ XFCE theme defaults: GTK=${GTK_THEME}, window=${WM_THEME} (${BORDER} px edges), icons=${ICON_THEME}, cursor=${CURSOR_THEME} (${CURSOR_SIZE})"
echo "   ${XSETTINGS_XML}"
echo "   ${XFWM4_XML}"
