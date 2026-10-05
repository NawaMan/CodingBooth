#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# fira-code-nerd-font--setup.sh — installs the Nerd Fonts-patched Fira Code
# family system-wide. Patched with icon/powerline glyphs, so shell prompts
# (starship, p10k-style) and CLI tools that print Nerd Font icons (lsd, exa,
# ...) render correctly instead of showing tofu boxes.
#
# Shared by every desktop variant's default terminal (xfce--setup.sh,
# kde--setup.sh, lxqt--setup.sh, wayland--setup.sh), called the same way each
# already calls python--setup.sh: "${SETUPS_DIR}/fira-code-nerd-font--setup.sh"

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
- Installs the Fira Code Nerd Font family to /usr/share/fonts/truetype/fira-code-nerd-font
- Family names registered with fontconfig: "FiraCode Nerd Font", "FiraCode Nerd Font Mono",
  "FiraCode Nerd Font Propo"
- Idempotent: a no-op if the font is already installed
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
FONT_DEFAULT_VER="3.4.0"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

FONT_DIR="/usr/share/fonts/truetype/fira-code-nerd-font"

# Already installed (e.g. a second desktop variant's setup calling this again).
if [[ -f "${FONT_DIR}/FiraCodeNerdFontMono-Regular.ttf" ]]; then
  echo "ℹ️  Fira Code Nerd Font already installed at ${FONT_DIR}"
  exit 0
fi

# The base image already carries curl and unzip, and the desktop variants
# already carry fontconfig (a transitive dependency of their GTK/Qt stacks);
# only pay for apt when this script is run somewhere leaner (e.g. codeserver,
# which installs no desktop toolkit at all).
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
echo "⬇️  Installing Fira Code Nerd Font v${FONT_VERSION} ..."
mkdir -p "$FONT_DIR"
TMP_FONT_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v${FONT_VERSION}/FiraCode.zip" \
  -o "${TMP_FONT_DIR}/FiraCode.zip"
unzip -o -q "${TMP_FONT_DIR}/FiraCode.zip" -d "$TMP_FONT_DIR"
find "$TMP_FONT_DIR" -name '*.ttf' -exec install -m 644 {} "$FONT_DIR/" \;
rm -rf "$TMP_FONT_DIR"
fc-cache -f "$FONT_DIR" >/dev/null

echo "✅ Fira Code Nerd Font v${FONT_VERSION} installed to ${FONT_DIR}"
cat <<'EON'
ℹ️ Ready to use:
- Family: "FiraCode Nerd Font Mono" (recommended for terminals, strictly monospaced)
- Also installed: "FiraCode Nerd Font", "FiraCode Nerd Font Propo"
- See: https://github.com/ryanoasis/nerd-fonts
EON
