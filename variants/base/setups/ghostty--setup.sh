#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

# ghostty--setup.sh — installs the Ghostty terminal emulator from a pinned,
# checksum-verified build for this Ubuntu release (26.04 or 24.04).
#
# Why not apt / upstream: Ghostty publishes no Linux binaries of its own, and
# Ubuntu only packages it from 25.10 on — noble has nothing, and 26.04's is a
# release behind this pin. The community build at
# https://github.com/mkasberg/ghostty-ubuntu publishes one .deb per Ubuntu
# release and arch, built from the tagged upstream source; that is what this
# installs, pinned below with the SHA256 of each .deb.
#
# To bump: pick a release from that repo, download
# ghostty_<ver>_{amd64,arm64}_{26.04,24.04}.deb, `sha256sum` all four, and
# update GHOSTTY_VERSION and every SHA256 together.
#
# Ghostty is GTK4 + OpenGL. Verified to run against a booth's Xvnc session via
# Mesa's llvmpipe software rasterizer (it reports "loaded OpenGL 4.5") — no
# host GPU needed.
#
# This is an *alternate* terminal for the desktop variants (desktop-xfce,
# desktop-kde, desktop-lxqt, desktop-wayland) — it does not replace each
# desktop's own default terminal (xfce4-terminal, Konsole, qterminal, foot).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <deb-version> --sha256 <hex>]

Examples:
  $0                                               # install the pinned Ghostty build
  $0 --version 1.3.2-0.ppa1 --sha256 <sha-of-deb>  # a different build, for this arch

Notes:
- Installs Ghostty to /usr/bin/ghostty (with its terminfo and .desktop launcher)
- Supports amd64 and arm64
- <deb-version> is the version in the .deb's file name (ghostty_<deb-version>_<arch>_<ubuntu-version>.deb)
- A version other than the pinned one must come with its .deb's SHA256
- The first container start seeds ~/.config/ghostty/config (never overwrites it):
  from /opt/codingbooth/ghostty/config when a setup put one there (ghostty-fancy),
  else a minimal FiraCode Nerd Font default
USAGE
}

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

# ---- pinned release ----
GHOSTTY_VERSION="1.3.1-0.ppa2"
GHOSTTY_SHA256_AMD64_2604="653fa1819b4d9d592184472b0303f06b3e1b21b2e3502858d128abf17fe7965c"
GHOSTTY_SHA256_ARM64_2604="a8128fe0106ddb803e29ad716b9ca0547fa13e45c2f7ff284ec7f6a14d97192d"
GHOSTTY_SHA256_AMD64_2404="478d440153ef544426418efc7d6d8901715359f452c46be29071901a94b8cd47"
GHOSTTY_SHA256_ARM64_2404="91063815b6ce3d834d59714b4ad0310f744448b6716836d035b3d331d1923363"

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

# ---- release + arch mapping (assets are named <arch>_<ubuntu-version>) ----
UBUNTU_VERSION="$(. /etc/os-release && echo "${VERSION_ID:-}")"
case "$UBUNTU_VERSION" in
  26.04|24.04) ;;
  *) echo "❌ Unsupported Ubuntu release: ${UBUNTU_VERSION:-unknown} (need 26.04 or 24.04)" >&2; exit 1 ;;
esac
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64|arm64) ;;
  *) echo "❌ Unsupported arch: $ARCH (need amd64 or arm64)" >&2; exit 1 ;;
esac
PINNED_SHA_VAR="GHOSTTY_SHA256_${ARCH^^}_${UBUNTU_VERSION//./}"
PINNED_SHA="${!PINNED_SHA_VAR}"

if [[ -z "$REQ_VER" || "$REQ_VER" == "$GHOSTTY_VERSION" ]]; then
  VERSION="$GHOSTTY_VERSION"
  SHA256="${REQ_SHA:-$PINNED_SHA}"
else
  if [[ -z "$REQ_SHA" ]]; then
    echo "❌ --version ${REQ_VER} needs --sha256 <hex> for ghostty_${REQ_VER}_${ARCH}_${UBUNTU_VERSION}.deb" >&2
    echo "   (only ${GHOSTTY_VERSION} has a checksum pinned in this script)" >&2
    exit 2
  fi
  VERSION="$REQ_VER"
  SHA256="$REQ_SHA"
fi

# The release tag spells the version with '-' where the file name has '.'
# before the ppa suffix: file 1.3.1-0.ppa2 lives under tag 1.3.1-0-ppa2.
TAG="${VERSION//.ppa/-ppa}"

export DEBIAN_FRONTEND=noninteractive
echo "🔧 Installing Ghostty ${VERSION} (${ARCH})…"

# ---- download + verify ----
ASSET="ghostty_${VERSION}_${ARCH}_${UBUNTU_VERSION}.deb"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/mkasberg/ghostty-ubuntu/releases/download/${TAG}/${ASSET}" \
  -o "${TMP_DIR}/${ASSET}"

echo "🔐 Verifying checksum…"
echo "${SHA256}  ${TMP_DIR}/${ASSET}" | sha256sum -c -

# ---- install ----
# apt resolves the .deb's GTK4/libadwaita dependencies; desktop variants
# already carry most of them.
apt-get update
apt-get install -y --no-install-recommends "${TMP_DIR}/${ASSET}"
rm -rf /var/lib/apt/lists/*

# Shared with every desktop variant's default terminal — idempotent, so this
# is a no-op if a desktop setup already installed it. The seeded default
# config below uses it.
SETUPS_DIR=${SETUPS_DIR:-/opt/codingbooth/setups}
"${SETUPS_DIR}/fira-code-nerd-font--setup.sh"

# Surface it as a desktop icon, same as every other desktop app in the
# catalog. No-op on non-desktop variants.
cb-desktop-icon.sh com.mitchellh.ghostty.desktop

# ---- startup script: seed a config once per home, at container start ----
# Build-time HOME is /root, not the runtime user's home, so the config must be
# written at container start (like kitty--setup.sh) rather than baked in here.
# A setup that wants a richer config (ghostty-fancy--setup.sh) drops it at
# /opt/codingbooth/ghostty/config; it is read at start time, so the order the
# two setups ran in does not matter. Only writing when the file is still
# absent means a later edit made by hand is never overwritten.
STARTUP_FILE="/usr/share/startup.d/57-cb-ghostty--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
set -uo pipefail

CONF="$HOME/.config/ghostty/config"
[[ -f "$CONF" ]] && exit 0

mkdir -p "$(dirname "$CONF")"
if [[ -f /opt/codingbooth/ghostty/config ]]; then
  cp /opt/codingbooth/ghostty/config "$CONF"
  echo "✅ cb-ghostty: seeded $CONF from /opt/codingbooth/ghostty/config"
else
  cat > "$CONF" <<'GCONF'
font-family = "FiraCode Nerd Font Mono"
font-size = 11
GCONF
  echo "✅ cb-ghostty: seeded default font in $CONF"
fi
STARTUP
chmod 0755 "$STARTUP_FILE"

echo "✅ Ghostty installed:"
ghostty --version | head -1

cat <<'EON'
ℹ️ Ready to use:
- Launch "Ghostty" from the desktop icon or app menu, or run `ghostty` in a terminal.
- Config: ~/.config/ghostty/config — seeded once at container start (edit it
  there afterwards; the seed never overwrites an existing file).
  Reload a running window with Ctrl+Shift+, ; check it with `ghostty +validate-config`.
- This is an alternate terminal — the desktop's own default terminal is unchanged.
EON
