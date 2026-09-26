#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# i3-default--setup.sh — make i3 the desktop's window manager at login.
#
# Run after i3--setup.sh (the i3 template's +default extension). Without it, i3
# is installed but the desktop logs in on its own window manager, and start-i3
# (or the "Tiling Window Manager (i3)" icon) switches over. stop-i3 still
# switches back either way.
#
#   XFCE — xfce4-session's system default (Failsafe session) runs i3 instead of
#          xfwm4 and drops xfdesktop, which i3 would tile as an ordinary
#          full-screen window. The two autostarts that assume xfdesktop are
#          hidden: xfce-set-wallpaper (it runs `xfdesktop --reload`, which
#          *starts* xfdesktop) and cb-xfce-arrange-icons.
#   LXQt — start-lxqt and the system session.conf default to i3 instead of
#          openbox, and the pcmanfm-qt desktop autostarts are hidden
#          (lxqt-set-wallpaper only waits for one, so it is harmless).
#
# Homes that already have a session config keep theirs.
#
# Usage: i3-default--setup.sh
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v i3 &>/dev/null || [[ ! -x /usr/local/bin/start-i3 ]]; then
  skip_setup "$SCRIPT_NAME" "i3 is not set up (i3--setup.sh skipped or has not run)"
fi

hide_autostart() {
  local f="/etc/xdg/autostart/$1"
  [[ -f "$f" ]] || return 0
  grep -q '^Hidden=true$' "$f" || echo 'Hidden=true' >> "$f"
}

if command -v xfce4-session &>/dev/null; then
  # Client0 is the window manager; Client4 is xfdesktop. Removing a client
  # means lowering Count too, or xfce4-session looks for a Client4 that is gone.
  SESSION_XML=/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml
  if [[ ! -f "$SESSION_XML" ]]; then
    echo "❌ ${SESSION_XML} not found" >&2
    exit 2
  fi
  sed -i 's|<value type="string" value="xfwm4"/>|<value type="string" value="i3"/>|' "$SESSION_XML"
  if grep -q '<value type="string" value="xfdesktop"/>' "$SESSION_XML"; then
    sed -i \
      -e '/<property name="Client4_Command" type="array">/,/<property name="Client4_PerScreen"/d' \
      -e 's|<property name="Count" type="int" value="5"/>|<property name="Count" type="int" value="4"/>|' \
      "$SESSION_XML"
  fi
  if grep -qE 'value="(xfwm4|xfdesktop)"' "$SESSION_XML" \
     || ! grep -q '<value type="string" value="i3"/>' "$SESSION_XML" \
     || ! grep -q '<property name="Count" type="int" value="4"/>' "$SESSION_XML"; then
    echo "❌ Failed to switch ${SESSION_XML} to i3" >&2
    exit 2
  fi
  hide_autostart xfce-set-wallpaper.desktop
  hide_autostart cb-xfce-arrange-icons.desktop
  echo "✅ XFCE logs in on i3 (${SESSION_XML})"

elif command -v startlxqt &>/dev/null; then
  STARTER=/usr/local/bin/start-lxqt
  if [[ -f "$STARTER" ]]; then
    sed -i 's|: "${LXQT_WM:=openbox}"|: "${LXQT_WM:=i3}"|' "$STARTER"
    if ! grep -q ': "${LXQT_WM:=i3}"' "$STARTER"; then
      echo "❌ Failed to switch ${STARTER} to i3" >&2
      exit 2
    fi
  fi
  LXQT_CONF=/etc/xdg/lxqt/session.conf
  if [[ -f "$LXQT_CONF" ]] && grep -q '^window_manager=' "$LXQT_CONF"; then
    sed -i 's|^window_manager=.*|window_manager=i3|' "$LXQT_CONF"
  else
    mkdir -p "$(dirname "$LXQT_CONF")"
    printf '[General]\nwindow_manager=i3\n' >> "$LXQT_CONF"
  fi
  hide_autostart lxqt-desktop.desktop
  hide_autostart lxqt-wallpaper.desktop
  echo "✅ LXQt logs in on i3 (${STARTER}, ${LXQT_CONF})"

else
  skip_setup "$SCRIPT_NAME" "neither XFCE nor LXQt is installed"
fi
