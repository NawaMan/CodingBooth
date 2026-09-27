#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# kitty-fancy--setup.sh — a styled Kitty look: JetBrains Mono Nerd Font, roomy
# padding, a steady block cursor, a slanted powerline tab bar, a Tokyo Night
# palette (Omarchy's kitty.conf), and Shift/Ctrl+Insert paste/copy. Same idea
# as ghostty-fancy--setup.sh / alacritty-fancy--setup.sh.
#
# Writes the config to /opt/codingbooth/kitty/kitty.conf, which
# kitty--setup.sh's startup script copies into ~/.config/kitty/kitty.conf on
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

CONF=/opt/codingbooth/kitty/kitty.conf
install -d "$(dirname "$CONF")"
cat > "$CONF" <<'KCONF'
# Omarchy-style Kitty
# https://github.com/omacom/omarchy/blob/master/etc/xdg/kitty/kitty.conf

font_family      JetBrainsMono Nerd Font
bold_italic_font auto
font_size        12.0

window_padding_width 14
hide_window_decorations no
confirm_os_window_close 0

map ctrl+insert copy_to_clipboard
map shift+insert paste_from_clipboard
map shift+enter send_text all \e[13;2u
map alt+shift+enter send_text all \e[13;4u

cursor_shape block
cursor_blink_interval 0
shell_integration no-cursor
enable_audio_bell no

tab_bar_edge        bottom
tab_bar_style       powerline
tab_powerline_style slanted
tab_title_template  {title}{' :{}:'.format(num_windows) if num_windows > 1 else ''}

# Tokyo Night (classic Omarchy default look)
foreground            #c0caf5
background            #1a1b26
selection_foreground  #c0caf5
selection_background  #33467c
cursor                #c0caf5
cursor_text_color     #1a1b26

color0  #15161e
color1  #f7768e
color2  #9ece6a
color3  #e0af68
color4  #7aa2f7
color5  #bb9af7
color6  #7dcfff
color7  #a9b1d6
color8  #414868
color9  #f7768e
color10 #9ece6a
color11 #e0af68
color12 #7aa2f7
color13 #bb9af7
color14 #7dcfff
color15 #c0caf5

active_tab_foreground   #1a1b26
active_tab_background   #7aa2f7
inactive_tab_foreground #545c7e
inactive_tab_background #16161e
KCONF
chmod 0644 "$CONF"

echo "✅ Kitty fancy config written to ${CONF}"
cat <<'EON'
ℹ️ Ready to use:
- Seeded into ~/.config/kitty/kitty.conf on the first container start (only if
  that file does not exist yet) — edit it there afterwards; reload a running
  Kitty with Ctrl+Shift+F5.
- Font: JetBrainsMono Nerd Font 12pt; palette: Tokyo Night; tabs: bottom, powerline.
- Shift+Insert pastes, Ctrl+Insert copies.
EON
