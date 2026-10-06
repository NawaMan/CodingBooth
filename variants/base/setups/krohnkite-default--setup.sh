#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# krohnkite-default--setup.sh — tile the KDE desktop with Krohnkite from login.
#
# Run after krohnkite--setup.sh (the krohnkite template's +default extension).
# Without it, Krohnkite is installed but off, and start-krohnkite (or the
# "Tiling for KDE (Krohnkite)" icon) turns it on. Sets KWin's system default in
# /etc/xdg/kwinrc; stop-krohnkite writes the user's own kwinrc, which wins, so
# turning it off stays off until start-krohnkite.
#
# Usage: krohnkite-default--setup.sh
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

install -d -m 0755 /etc/xdg
kwriteconfig6 --file /etc/xdg/kwinrc --group Plugins --key krohnkiteEnabled true
chmod 0644 /etc/xdg/kwinrc

echo "✅ Krohnkite tiling on at login (/etc/xdg/kwinrc; stop-krohnkite turns it off)"
