#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# sway-gaps--setup.sh — a small gap between sway windows, and between the
# windows and the panel, so the wallpaper shows at their edges.
#
# Run after sway--setup.sh (the sway template's +gaps extension). Writes
# /etc/sway/config.d/gaps.conf.
#
# Usage: sway-gaps--setup.sh [PIXELS]      (default: 8)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
SWAY_CONFIG=/etc/sway/config
if ! command -v sway &>/dev/null || [[ ! -f /opt/codingbooth/wayland-compositor ]]; then
  skip_setup "$SCRIPT_NAME" "sway is not set up (sway--setup.sh skipped or has not run)"
fi

GAP="${1:-8}"
if [[ ! "$GAP" =~ ^[0-9]+$ ]]; then
  echo "❌ Gap must be a number of pixels, got '${GAP}'" >&2
  exit 1
fi

install -d -m 0755 /etc/sway/config.d
printf '# Installed by sway-gaps--setup.sh.\ngaps inner %s\n' "$GAP" > /etc/sway/config.d/gaps.conf
chmod 0644 /etc/sway/config.d/gaps.conf

# See sway--setup.sh for why validating needs these.
dir="$(mktemp -d)"
if ! XDG_RUNTIME_DIR="$dir" WLR_BACKENDS=headless WLR_RENDERER=pixman \
     sway --unsupported-gpu -C -c "$SWAY_CONFIG" >/dev/null 2>&1; then
  rm -rf "$dir"
  echo "❌ ${SWAY_CONFIG} does not validate with gaps.conf" >&2
  exit 2
fi
rm -rf "$dir"

echo "✅ sway window gap: ${GAP}px (/etc/sway/config.d/gaps.conf)"
