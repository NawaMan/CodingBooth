#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# alacritty--setup.sh — installs the Alacritty terminal emulator via apt.
#
# Alacritty is GPU-accelerated (OpenGL). Verified to run against a booth's
# Xvnc/wayvnc session via Mesa's llvmpipe software rasterizer (no host GPU
# needed) — `glxinfo -B` reports a working GL 4.5 core context under Xvnc.
#
# This is an *alternate* terminal for the X11/Wayland desktop variants
# (desktop-xfce, desktop-kde, desktop-lxqt, desktop-wayland) — it does not
# replace each desktop's own default terminal (xfce4-terminal, Konsole,
# qterminal, foot).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

export DEBIAN_FRONTEND=noninteractive
echo "🔧 Installing Alacritty…"

apt-get update
# ncurses-term: Ubuntu's alacritty package does not ship its own terminfo entry
# (unlike kitty, which pulls one in automatically via the kitty-terminfo
# dependency) — without it, TERM=alacritty has no matching terminfo, and any
# program that does a strict terminfo lookup (readline, ncurses UIs, some
# terminal multiplexers) can misbehave. ncurses-term provides it.
apt-get install -y --no-install-recommends alacritty ncurses-term
rm -rf /var/lib/apt/lists/*

# Shared with every desktop variant's default terminal — idempotent, so this
# is a no-op if a desktop setup already installed it.
SETUPS_DIR=${SETUPS_DIR:-/opt/codingbooth/setups}
"${SETUPS_DIR}/fira-code-nerd-font--setup.sh"

# Surface it as a desktop icon, same as every other desktop app in the
# catalog (firefox, gimp, inkscape). No-op on non-desktop variants.
cb-desktop-icon.sh alacritty

# ---- startup script: seed a default font once per home, at container start ----
# Build-time HOME is /root, not the runtime user's home, so the config must be
# written at container start (like xfce--setup.sh's terminalrc seeding) rather
# than baked in here. Only writing it when the file is still absent means a
# later font change made by hand is never overwritten on the next session.
STARTUP_FILE="/usr/share/startup.d/57-cb-alacritty--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -uo pipefail

CONF="$HOME/.config/alacritty/alacritty.toml"
[[ -f "$CONF" ]] && exit 0

mkdir -p "$(dirname "$CONF")"
cat > "$CONF" <<'TOML'
[font]
size = 11.0

[font.normal]
family = "FiraCode Nerd Font Mono"
TOML

echo "✅ cb-alacritty: seeded default font in $CONF"
STARTUP
chmod 0755 "$STARTUP_FILE"

echo "✅ Alacritty installed:"
alacritty --version

cat <<'EON'
ℹ️ Ready to use:
- Launch "Alacritty" from your desktop's app menu, or run `alacritty` in a terminal.
- Default font: FiraCode Nerd Font Mono, 11pt — seeded once at container start
  into ~/.config/alacritty/alacritty.toml (edit it there afterwards; the seed
  never overwrites an existing file).
- This is an alternate terminal — the desktop's own default terminal is
  unchanged.
EON
