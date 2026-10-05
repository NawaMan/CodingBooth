#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# jetbrains-mono-nerd-font--setup.sh — installs the Nerd Fonts-patched
# JetBrains Mono family system-wide. Same shape as fira-code-nerd-font--setup.sh
# (icon/powerline glyphs, so prompts and icon-printing CLIs render instead of
# showing tofu boxes), minus the .woff2 siblings — nothing serves this one to a
# browser. Used by ghostty-fancy--setup.sh.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                  # install latest stable Nerd Fonts release
  $0 --version 3.4.0  # pin a specific Nerd Fonts release

Notes:
- Installs the JetBrains Mono Nerd Font family to /usr/share/fonts/truetype/jetbrains-mono-nerd-font
- Family names registered with fontconfig: "JetBrainsMono Nerd Font",
  "JetBrainsMono Nerd Font Mono", "JetBrainsMono Nerd Font Propo"
- Idempotent: a no-op if the font is already installed
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
FONT_DEFAULT_VER="3.5.1"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

FONT_DIR="/usr/share/fonts/truetype/jetbrains-mono-nerd-font"

# Already installed (a second setup calling this again).
if [[ -f "${FONT_DIR}/JetBrainsMonoNerdFont-Regular.ttf" ]]; then
  echo "ℹ️  JetBrains Mono Nerd Font already installed at ${FONT_DIR}"
  exit 0
fi

# The base image already carries curl and unzip, and the desktop variants
# already carry fontconfig; only pay for apt when this runs somewhere leaner.
if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v fc-cache >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates unzip fontconfig
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  FONT_VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
                | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
                | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$FONT_VERSION" ]]; then
    # See lazygit--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest Nerd Fonts release; using ${FONT_DEFAULT_VER}."
    FONT_VERSION="$FONT_DEFAULT_VER"
  fi
else
  FONT_VERSION="$REQ_VER"
fi

# ---- install the font ----
echo "⬇️  Installing JetBrains Mono Nerd Font v${FONT_VERSION} ..."
mkdir -p "$FONT_DIR"
TMP_FONT_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v${FONT_VERSION}/JetBrainsMono.zip" \
  -o "${TMP_FONT_DIR}/JetBrainsMono.zip"
unzip -o -q "${TMP_FONT_DIR}/JetBrainsMono.zip" -d "$TMP_FONT_DIR"
find "$TMP_FONT_DIR" -name '*.ttf' -exec install -m 644 {} "$FONT_DIR/" \;
rm -rf "$TMP_FONT_DIR"
fc-cache -f "$FONT_DIR" >/dev/null

echo "✅ JetBrains Mono Nerd Font v${FONT_VERSION} installed to ${FONT_DIR}"
cat <<'EON'
ℹ️ Ready to use:
- Family: "JetBrainsMono Nerd Font Mono" (strictly monospaced), "JetBrainsMono Nerd Font"
- Also installed: "JetBrainsMono Nerd Font Propo"
- See: https://github.com/ryanoasis/nerd-fonts
EON
