#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# i3-gaps--setup.sh — a small gap between i3 windows, and between the windows
# and the panel/dock, so the wallpaper shows at their edges.
#
# Run after i3--setup.sh (the i3 template's +gaps extension). Writes
# /etc/xdg/i3/config.d/gaps.conf; i3 4.22+ has gaps built in.
#
# Usage: i3-gaps--setup.sh [PIXELS]      (default: 8)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
I3_CONFIG=/etc/xdg/i3/config
if ! command -v i3 &>/dev/null || [[ ! -f "$I3_CONFIG" ]]; then
  skip_setup "$SCRIPT_NAME" "i3 is not set up (i3--setup.sh skipped or has not run)"
fi

GAP="${1:-8}"
if [[ ! "$GAP" =~ ^[0-9]+$ ]]; then
  echo "❌ Gap must be a number of pixels, got '${GAP}'" >&2
  exit 1
fi

install -d -m 0755 /etc/xdg/i3/config.d
printf '# Installed by i3-gaps--setup.sh.\ngaps inner %s\n' "$GAP" > /etc/xdg/i3/config.d/gaps.conf
chmod 0644 /etc/xdg/i3/config.d/gaps.conf

if ! i3 -C -c "$I3_CONFIG" >/dev/null; then
  i3 -C -c "$I3_CONFIG" >&2 || true
  echo "❌ ${I3_CONFIG} does not validate with gaps.conf" >&2
  exit 2
fi

echo "✅ i3 window gap: ${GAP}px (/etc/xdg/i3/config.d/gaps.conf)"
