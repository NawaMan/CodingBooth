#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# bismuth-gaps--setup.sh — a small gap between Bismuth's tiled windows, and
# between the windows and the screen edges/panel, so the wallpaper shows.
#
# Run after bismuth--setup.sh (the bismuth template's +gaps extension). Writes
# Bismuth's gap settings as KWin's system default in /etc/xdg/kwinrc; changes
# made in System Settings → Window Tiling go to the user's kwinrc and win.
#
# Usage: bismuth-gaps--setup.sh [PIXELS]      (default: 8)
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

GAP="${1:-8}"
if [[ ! "$GAP" =~ ^[0-9]+$ ]]; then
  echo "❌ Gap must be a number of pixels, got '${GAP}'" >&2
  exit 1
fi

install -d -m 0755 /etc/xdg
for key in tileLayoutGap screenGapLeft screenGapRight screenGapTop screenGapBottom; do
  kwriteconfig5 --file /etc/xdg/kwinrc --group Script-bismuth --key "$key" "$GAP"
done
chmod 0644 /etc/xdg/kwinrc

echo "✅ Bismuth window gap: ${GAP}px (/etc/xdg/kwinrc)"
