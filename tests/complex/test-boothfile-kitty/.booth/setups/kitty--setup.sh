#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# kitty--setup.sh — installs the Kitty terminal emulator from a pinned,
# checksum-verified upstream release.
#
# Why not apt: Ubuntu 24.04 ships Kitty 0.32.2 in `universe`, and its security
# fixes go to Ubuntu Pro (ESM Apps) only. The public package is still exposed to
# CVE-2026-72913 (fixed 0.48.2 — escape sequences that write to the shell's
# stdin, i.e. displaying untrusted output runs commands), CVE-2026-42850 and
# CVE-2026-33642 (fixed 0.47.0). So Kitty comes from its own GitHub release,
# pinned below with SHA256s taken from the GPG-verified assets (signed by
# Kovid Goyal, key 3CE1780F78DD88DF45194FD706BC317B515ACE7C).
#
# To bump: download kitty-<ver>-{x86_64,arm64}.txz and their .sig files from
# https://github.com/kovidgoyal/kitty/releases, `gpg --verify` each against that
# key, then update KITTY_VERSION and both SHA256s together.
#
# Kitty is GPU-accelerated (OpenGL). Verified to run against a booth's
# Xvnc/wayvnc session via Mesa's llvmpipe software rasterizer (no host GPU
# needed) — `glxinfo -B` reports a working GL 4.5 core context under Xvnc.
#
# This is an *alternate* terminal for the X11/Wayland desktop variants
# (desktop-xfce, desktop-kde, desktop-lxqt, desktop-wayland) — it does not
# replace each desktop's own default terminal (xfce4-terminal, Konsole,
# qterminal, foot).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z> --sha256 <hex>]

Examples:
  $0                                         # install the pinned Kitty release
  $0 --version 0.49.2 --sha256 <sha-of-txz>  # a different release, for this arch

Notes:
- Installs Kitty to /opt/kitty, with kitty and kitten on /usr/local/bin
- Supports amd64 and arm64
- A version other than the pinned one must come with its archive's SHA256
USAGE
}

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

# ---- pinned release ----
KITTY_VERSION="0.49.1"
KITTY_SHA256_X86_64="8cfd68ed484d9a32e4e389abffe1a0ec6e0fbd7be5c9ea1c4fa41b9ead4af791"
KITTY_SHA256_ARM64="828fcfe3e165c84d830f82545b6d568655b2620d77b7d5a4360e082bd9ba744b"

REQ_VER=""
REQ_SHA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift || true ;;
    --sha256)  shift; REQ_SHA="${1:-}"; shift || true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch mapping (release assets are named x86_64 / arm64) ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64"; PINNED_SHA="$KITTY_SHA256_X86_64" ;;
  arm64) ARCH="arm64";  PINNED_SHA="$KITTY_SHA256_ARM64"  ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)" >&2; exit 1 ;;
esac

if [[ -z "$REQ_VER" || "$REQ_VER" == "$KITTY_VERSION" ]]; then
  VERSION="$KITTY_VERSION"
  SHA256="${REQ_SHA:-$PINNED_SHA}"
else
  if [[ -z "$REQ_SHA" ]]; then
    echo "❌ --version ${REQ_VER} needs --sha256 <hex> for kitty-${REQ_VER}-${ARCH}.txz" >&2
    echo "   (only ${KITTY_VERSION} has a checksum pinned in this script)" >&2
    exit 2
  fi
  VERSION="$REQ_VER"
  SHA256="$REQ_SHA"
fi

export DEBIAN_FRONTEND=noninteractive
echo "🔧 Installing Kitty ${VERSION} (${ARCH})…"

# The release bundles its own Python, OpenSSL, sqlite, and libiconv, but links
# the desktop's X11/Wayland/font stack from the system. Desktop variants already
# carry all of it (this is then a no-op); listing it keeps the script working on
# a leaner image, the way the apt package's dependencies used to.
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl xz-utils \
  libgl1 libegl1 \
  libx11-6 libx11-xcb1 libxcb1 libxcb-xkb1 libxcursor1 \
  libxkbcommon0 libxkbcommon-x11-0 libwayland-client0 \
  libfontconfig1 libfreetype6 libharfbuzz0b libcairo2 libpixman-1-0 \
  libpng16-16t64 liblcms2-2 libbrotli1 libexpat1 libdbus-1-3 libreadline8t64
rm -rf /var/lib/apt/lists/*

# ---- download + verify ----
ASSET="kitty-${VERSION}-${ARCH}.txz"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/kovidgoyal/kitty/releases/download/v${VERSION}/${ASSET}" \
  -o "${TMP_DIR}/${ASSET}"

echo "🔐 Verifying checksum…"
echo "${SHA256}  ${TMP_DIR}/${ASSET}" | sha256sum -c -

# ---- install to /opt/kitty ----
rm -rf /opt/kitty
install -d /opt/kitty
tar -xJf "${TMP_DIR}/${ASSET}" -C /opt/kitty

ln -sfn /opt/kitty/bin/kitty  /usr/local/bin/kitty
ln -sfn /opt/kitty/bin/kitten /usr/local/bin/kitten

# Launchers + icons where the desktop looks for them. Exec=kitty resolves via
# /usr/local/bin, and Icon=kitty via the hicolor theme.
install -d /usr/share/applications
install -m 644 /opt/kitty/share/applications/kitty.desktop      /usr/share/applications/kitty.desktop
install -m 644 /opt/kitty/share/applications/kitty-open.desktop /usr/share/applications/kitty-open.desktop
cp -r /opt/kitty/share/icons/hicolor/. /usr/share/icons/hicolor/
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
fi

# TERM=xterm-kitty — the apt package pulled in kitty-terminfo for this; ncurses
# searches /etc/terminfo first, so Kitty's own entry wins without touching a
# dpkg-owned file.
install -d /etc/terminfo/x
install -m 644 /opt/kitty/lib/kitty/terminfo/x/xterm-kitty /etc/terminfo/x/xterm-kitty

# Shared with every desktop variant's default terminal — idempotent, so this
# is a no-op if a desktop setup already installed it.
SETUPS_DIR=${SETUPS_DIR:-/opt/codingbooth/setups}
"${SETUPS_DIR}/fira-code-nerd-font--setup.sh"

# Surface it as a desktop icon, same as every other desktop app in the
# catalog (firefox, gimp, inkscape). No-op on non-desktop variants.
cb-desktop-icon.sh kitty

# ---- startup script: seed a default font once per home, at container start ----
# Build-time HOME is /root, not the runtime user's home, so the config must be
# written at container start (like xfce--setup.sh's terminalrc seeding) rather
# than baked in here. Only writing it when the file is still absent means a
# later font change made by hand is never overwritten on the next session.
STARTUP_FILE="/usr/share/startup.d/57-cb-kitty--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -uo pipefail

CONF="$HOME/.config/kitty/kitty.conf"
[[ -f "$CONF" ]] && exit 0

mkdir -p "$(dirname "$CONF")"
cat > "$CONF" <<'KCONF'
font_family      FiraCode Nerd Font Mono
font_size        11.0
KCONF

echo "✅ cb-kitty: seeded default font in $CONF"
STARTUP
chmod 0755 "$STARTUP_FILE"

echo "✅ Kitty installed:"
kitty --version

cat <<'EON'
ℹ️ Ready to use:
- Launch "kitty" from your desktop's app menu, or run `kitty` in a terminal.
- Default font: FiraCode Nerd Font Mono, 11pt — seeded once at container start
  into ~/.config/kitty/kitty.conf (edit it there afterwards; the seed never
  overwrites an existing file).
- This is an alternate terminal — the desktop's own default terminal is
  unchanged.
EON
