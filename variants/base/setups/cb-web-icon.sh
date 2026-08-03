#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# cb-web-icon.sh — register a desktop icon for a booth web service (an HTTP
# server on an internal port, e.g. JupyterLab). The icon opens the service in a
# browser via cb-web-open at click time.
#
# It writes two things and reuses cb-desktop-icon.sh to place the launcher:
#   • /etc/cb-web-services/<id>.conf     — descriptor read by cb-web-open
#   • /usr/share/applications/<id>-web.desktop — launcher (Exec=cb-web-open <id>)
# The launcher is then registered into /etc/skel/Desktop — the same registry the
# app icons use — so booth-entry seeds it to ~/Desktop, XFCE arranges it, and the
# Wayland waybar turns it into a panel button, all for free. No-ops off-desktop.
#
# Usage:
#   cb-web-icon.sh --id <id> --name <Name> [--icon <icon>] \
#                  [--port-env <ENV>] --port <default-port> \
#                  [--path <url-path>] [--token-env <ENV>] [--start <command>]

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ID=""; NAME=""; ICON="applications-internet"
PORT_ENV=""; PORT_DEFAULT=""; URL_PATH="/"; TOKEN_ENV=""; START_CMD=""

while [ $# -gt 0 ]; do
  case "$1" in
    --id)        ID="$2";           shift 2 ;;
    --name)      NAME="$2";         shift 2 ;;
    --icon)      ICON="$2";         shift 2 ;;
    --port-env)  PORT_ENV="$2";     shift 2 ;;
    --port)      PORT_DEFAULT="$2"; shift 2 ;;
    --path)      URL_PATH="$2";     shift 2 ;;
    --token-env) TOKEN_ENV="$2";    shift 2 ;;
    --start)     START_CMD="$2";    shift 2 ;;
    *) echo "cb-web-icon: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$ID" ] && [ -n "$NAME" ] && [ -n "$PORT_DEFAULT" ] \
  || { echo "cb-web-icon: --id, --name and --port are required" >&2; exit 2; }

# Web-service icons only make sense where a desktop environment exists.
"$SCRIPT_DIR/cb-has-desktop.sh" || exit 0

# An --icon naming an existing *file* is the app's own artwork — whatever its
# install dropped on disk (Excalidraw's favicon.svg, a favicon extracted from a
# war). Copy it somewhere stable and reference it by absolute path, which the
# desktop-entry spec allows and the Jupyter launcher already relies on. Anything
# else is passed through as a themed icon name.
#
# The copy matters: the source may live in a build tree that a later cleanup
# step removes, and an Icon= pointing at a deleted file renders as a blank.
if [ -f "$ICON" ]; then
  CB_ICON_DIR="${CB_ICON_DIR:-/usr/share/codingbooth/icons}"
  mkdir -p "$CB_ICON_DIR"
  icon_ext="${ICON##*.}"
  case "$icon_ext" in
    svg|png|ico|xpm|jpg|jpeg) : ;;
    *) icon_ext="png" ;;   # unknown extension: GdkPixbuf sniffs content anyway
  esac
  cp -f "$ICON" "${CB_ICON_DIR}/${ID}.${icon_ext}"
  chmod 0644 "${CB_ICON_DIR}/${ID}.${icon_ext}"
  ICON="${CB_ICON_DIR}/${ID}.${icon_ext}"
  echo "🎨 icon installed: ${ICON}"
fi

# Descriptor consumed by cb-web-open at click time.
CB_WEB_CONF_DIR="${CB_WEB_CONF_DIR:-/etc/cb-web-services}"
mkdir -p "$CB_WEB_CONF_DIR"
cat > "${CB_WEB_CONF_DIR}/${ID}.conf" <<EOF
PORT_ENV=${PORT_ENV}
PORT_DEFAULT=${PORT_DEFAULT}
URL_PATH=${URL_PATH}
TOKEN_ENV=${TOKEN_ENV}
START_CMD=${START_CMD}
EOF

# Launcher in the applications dir so gtk-launch (Wayland buttons) and app menus
# resolve it, then register it as a desktop icon via the shared helper.
APPS_DIR="${APPS_DIR:-/usr/share/applications}"
mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/${ID}-web.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${NAME}
Exec=cb-web-open ${ID}
Icon=${ICON}
Terminal=false
Categories=Network;Development;
EOF
chmod 0644 "$APPS_DIR/${ID}-web.desktop"

"$SCRIPT_DIR/cb-desktop-icon.sh" "${ID}-web.desktop"
echo "🌐 web-service icon registered: ${NAME} (${ID})"
