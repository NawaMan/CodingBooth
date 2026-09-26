#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Workspace-local setup: desktop-xfce bakes Firefox in unconditionally
# (variants/desktop-xfce/Dockerfile runs firefox--setup.sh directly, it is not
# a --select-able template), so removing it for this one example means
# uninstalling it after the fact rather than just not selecting it. Runs after
# firefox--setup.sh (this project's own `setup` steps compile as later layers
# on top of the desktop-xfce image, which already has Firefox installed).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }

if command -v firefox >/dev/null 2>&1; then
  apt-get remove -y firefox
  rm -f /etc/apt/preferences.d/mozillateam-firefox
  # firefox--setup.sh registered it as x-www-browser (default when Chrome was
  # absent at that point in the build); re-point at Chrome now that it's gone.
  update-alternatives --remove x-www-browser /usr/bin/firefox 2>/dev/null || true
  if command -v google-chrome >/dev/null 2>&1; then
    update-alternatives --set x-www-browser /usr/bin/google-chrome 2>/dev/null || true
  fi
  echo "✅ Firefox removed"
else
  echo "ℹ️  Firefox not installed; nothing to remove"
fi

# Drop the desktop icon firefox--setup.sh registered under /etc/skel/Desktop
# (cb-desktop-icon.sh's registry — see that script for how entries land there).
rm -f /etc/skel/Desktop/firefox.desktop
echo "✅ Firefox desktop icon removed"
