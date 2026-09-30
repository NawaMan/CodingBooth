#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# krohnkite-gaps--setup.sh — a small gap between Krohnkite's tiled windows, and
# between the windows and the screen edges/panel, so the wallpaper shows.
#
# Run after krohnkite--setup.sh (the krohnkite template's +gaps extension).
# Writes Krohnkite's gap settings as KWin's system default in /etc/xdg/kwinrc;
# changes made in Krohnkite's settings page go to the user's kwinrc and win.
#
# Usage: krohnkite-gaps--setup.sh [PIXELS]      (default: 8)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v kwriteconfig6 &>/dev/null || [[ ! -x /usr/local/bin/start-krohnkite ]]; then
  skip_setup "$SCRIPT_NAME" "Krohnkite is not set up (krohnkite--setup.sh skipped or has not run)"
fi

GAP="${1:-8}"
if [[ ! "$GAP" =~ ^[0-9]+$ ]]; then
  echo "❌ Gap must be a number of pixels, got '${GAP}'" >&2
  exit 1
fi

install -d -m 0755 /etc/xdg
for key in screenGapBetween screenGapLeft screenGapRight screenGapTop screenGapBottom; do
  kwriteconfig6 --file /etc/xdg/kwinrc --group Script-krohnkite --key "$key" "$GAP"
done
chmod 0644 /etc/xdg/kwinrc

echo "✅ Krohnkite window gap: ${GAP}px (/etc/xdg/kwinrc)"
