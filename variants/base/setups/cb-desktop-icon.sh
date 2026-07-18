#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# cb-desktop-icon.sh — register a GUI app's launcher as a desktop icon.
#
# Copies the app's .desktop launcher into /etc/skel/Desktop. That directory is
# the single registry of "apps to surface on the desktop":
#   • booth-entry seeds it into each user's ~/Desktop (XFCE/KDE/LXQt),
#   • the Wayland variant turns each entry into a waybar panel button.
#
# Usage:
#   cb-desktop-icon.sh <app>...
#
# Each <app> may be:
#   • a path to a .desktop file           (e.g. "$DESKTOP_FILE")
#   • a .desktop basename in the app dir  (e.g. code.desktop)
#   • an app/command token                (e.g. gimp) — resolved to a launcher
#     by matching <token>.desktop, then a .desktop whose Exec command matches,
#     then a .desktop whose id contains the token.
#
# Apps that cannot be resolved are logged and skipped — this never fails a build,
# so setups can call it unconditionally. No-ops on non-desktop variants.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPS_DIR="${APPS_DIR:-/usr/share/applications}"
SKEL_DESKTOP="${SKEL_DESKTOP:-/etc/skel/Desktop}"

# Desktop launchers only make sense where a desktop environment exists.
"$SCRIPT_DIR/cb-has-desktop.sh" || exit 0

# Resolve an <app> argument to a launcher path under $APPS_DIR (or an explicit
# path). Prints the resolved path on success; returns non-zero when unresolved.
resolve_launcher() {
  local arg="$1" f base exec_bin

  # 1) explicit path to a .desktop file
  if [[ "$arg" == *.desktop && -f "$arg" ]]; then
    echo "$arg"; return 0
  fi
  # 2) a .desktop basename living in the applications dir
  if [[ "$arg" == *.desktop && -f "$APPS_DIR/$arg" ]]; then
    echo "$APPS_DIR/$arg"; return 0
  fi
  # 3) token → <token>.desktop
  if [[ -f "$APPS_DIR/$arg.desktop" ]]; then
    echo "$APPS_DIR/$arg.desktop"; return 0
  fi
  # 4) token → a launcher whose Exec command's basename matches
  for f in "$APPS_DIR"/*.desktop; do
    [ -f "$f" ] || continue
    exec_bin="$(sed -n 's/^Exec=//p' "$f" | head -1 | awk '{print $1}')"
    exec_bin="${exec_bin##*/}"
    if [[ -n "$exec_bin" && "$exec_bin" == "$arg" ]]; then
      echo "$f"; return 0
    fi
  done
  # 5) token → a launcher whose id contains the token (case-insensitive)
  for f in "$APPS_DIR"/*.desktop; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    if [[ "${base,,}" == *"${arg,,}"* ]]; then
      echo "$f"; return 0
    fi
  done

  return 1
}

mkdir -p "$SKEL_DESKTOP"

for arg in "$@"; do
  if src="$(resolve_launcher "$arg")"; then
    dest="$SKEL_DESKTOP/$(basename "$src")"
    cp -f "$src" "$dest"
    chmod 755 "$dest"
    echo "🖥️  desktop icon registered: $(basename "$src")  (from '$arg')"
  else
    echo "⚠️  cb-desktop-icon: no launcher found for '$arg'; skipped" >&2
  fi
done
