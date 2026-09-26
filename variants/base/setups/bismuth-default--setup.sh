#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# bismuth-default--setup.sh — tile the KDE desktop with Bismuth from login.
#
# Run after bismuth--setup.sh (the bismuth template's +default extension).
# Without it, Bismuth is installed but off, and start-bismuth (or the "Tiling
# for KDE (Bismuth)" icon) turns it on. Sets KWin's system default in
# /etc/xdg/kwinrc; stop-bismuth writes the user's own kwinrc, which wins, so
# turning it off stays off until start-bismuth.
#
# Usage: bismuth-default--setup.sh
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v kwriteconfig5 &>/dev/null || [[ ! -x /usr/local/bin/start-bismuth ]]; then
  skip_setup "$SCRIPT_NAME" "Bismuth is not set up (bismuth--setup.sh skipped or has not run)"
fi

install -d -m 0755 /etc/xdg
kwriteconfig5 --file /etc/xdg/kwinrc --group Plugins --key bismuthEnabled true
chmod 0644 /etc/xdg/kwinrc

echo "✅ Bismuth tiling on at login (/etc/xdg/kwinrc; stop-bismuth turns it off)"
