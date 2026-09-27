#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ghostty-fancy--setup.sh — a styled Ghostty look: JetBrains Mono Nerd Font,
# roomy padding, a flat toolbar, a steady block cursor, a Tokyo Night palette
# (Omarchy's default), and Shift/Ctrl+Insert paste/copy.
#
# Writes the config to /opt/codingbooth/ghostty/config, which
# ghostty--setup.sh's startup script copies into ~/.config/ghostty/config on
# the first container start (never over an existing file). Nothing is written
# under $HOME here — build-time HOME is /root, not the runtime user's.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

HOME=/root

# Its sibling, not /opt/codingbooth/setups: the font setup ships alongside this
# one, so a project's .booth/setups/ override of both resolves together.
SCRIPT_DIR="$(dirname "$0")"
"${SCRIPT_DIR}/jetbrains-mono-nerd-font--setup.sh"

CONF=/opt/codingbooth/ghostty/config
install -d "$(dirname "$CONF")"
cat > "$CONF" <<'GCONF'
font-family = "JetBrainsMono Nerd Font"
font-style = Regular
font-size = 12

window-padding-x = 14
window-padding-y = 14
window-theme = ghostty
confirm-close-surface = false
gtk-toolbar-style = flat

cursor-style = block
cursor-style-blink = false

# Tokyo Night-ish Omarchy default palette
background = #1a1b26
foreground = #c0caf5
cursor-color = #c0caf5
selection-background = #33467c
selection-foreground = #c0caf5

palette = 0=#15161e
palette = 1=#f7768e
palette = 2=#9ece6a
palette = 3=#e0af68
palette = 4=#7aa2f7
palette = 5=#bb9af7
palette = 6=#7dcfff
palette = 7=#a9b1d6
palette = 8=#414868
palette = 9=#f7768e
palette = 10=#9ece6a
palette = 11=#e0af68
palette = 12=#7aa2f7
palette = 13=#bb9af7
palette = 14=#7dcfff
palette = 15=#c0caf5

keybind = shift+insert=paste_from_clipboard
keybind = control+insert=copy_to_clipboard
GCONF
chmod 0644 "$CONF"

echo "✅ Ghostty fancy config written to ${CONF}"
cat <<'EON'
ℹ️ Ready to use:
- Seeded into ~/.config/ghostty/config on the first container start (only if
  that file does not exist yet) — edit it there afterwards.
- Font: JetBrainsMono Nerd Font 12pt; palette: Tokyo Night.
- Shift+Insert pastes, Ctrl+Insert copies.
EON
