#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# alacritty-fancy--setup.sh — a styled Alacritty look: JetBrains Mono Nerd
# Font, roomy padding, and a Tokyo Night palette (Omarchy's Alacritty
# skeleton). Same idea as ghostty-fancy--setup.sh.
#
# Writes the config to /opt/codingbooth/alacritty/alacritty.toml, which
# alacritty--setup.sh's startup script copies into
# ~/.config/alacritty/alacritty.toml on the first container start (never over
# an existing file). Nothing is written under $HOME here — build-time HOME is
# /root, not the runtime user's.

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

CONF=/opt/codingbooth/alacritty/alacritty.toml
install -d "$(dirname "$CONF")"
cat > "$CONF" <<'TOML'
# TERM as Omarchy sets it: xterm-256color is known everywhere (ssh hosts,
# other containers); alacritty's own entry only exists where ncurses-term is.
[env]
TERM = "xterm-256color"

[font]
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
bold = { family = "JetBrainsMono Nerd Font", style = "Bold" }
italic = { family = "JetBrainsMono Nerd Font", style = "Italic" }
size = 12

[window]
padding.x = 14
padding.y = 14
decorations = "Full"   # use "None" if you want the borderless Omarchy look

[colors.primary]
background = "#1a1b26"
foreground = "#c0caf5"

[colors.normal]
black   = "#15161e"
red     = "#f7768e"
green   = "#9ece6a"
yellow  = "#e0af68"
blue    = "#7aa2f7"
magenta = "#bb9af7"
cyan    = "#7dcfff"
white   = "#a9b1d6"

[colors.bright]
black   = "#414868"
red     = "#f7768e"
green   = "#9ece6a"
yellow  = "#e0af68"
blue    = "#7aa2f7"
magenta = "#bb9af7"
cyan    = "#7dcfff"
white   = "#c0caf5"
TOML
chmod 0644 "$CONF"

echo "✅ Alacritty fancy config written to ${CONF}"
cat <<'EON'
ℹ️ Ready to use:
- Seeded into ~/.config/alacritty/alacritty.toml on the first container start
  (only if that file does not exist yet) — edit it there afterwards; Alacritty
  reloads it live.
- Font: JetBrainsMono Nerd Font 12pt; palette: Tokyo Night.
EON
