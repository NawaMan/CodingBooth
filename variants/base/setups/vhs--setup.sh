#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                           # install latest VHS
  $0 --version 0.9.0           # pin specific version

Notes:
- Installs VHS (Charmbracelet) for recording terminal/TUI sessions from .tape scripts.
- Requires and installs ffmpeg for GIF/MP4 output.
- See: https://github.com/charmbracelet/vhs
- Usage: write a .tape file, then 'vhs your-demo.tape'
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) VHS_ARCH="x86_64" ;;
  arm64) VHS_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar ffmpeg
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/charmbracelet/vhs/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing VHS v${VERSION} (${VHS_ARCH}) + ffmpeg ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/charmbracelet/vhs/releases/download/v${VERSION}/vhs_${VERSION}_Linux_${VHS_ARCH}.tar.gz" -o "$TMP/vhs.tar.gz"
tar -xzf "$TMP/vhs.tar.gz" -C "$TMP"
install -m 755 "$TMP/vhs" /usr/local/bin/vhs

echo "✅ VHS installed."
echo -n "   vhs → "; vhs --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Create a recording script:   nano demo.tape
- Render to GIF + MP4:        vhs demo.tape
- Common .tape directives:
    Output demo.gif
    Output demo.mp4
    Set FontSize 18
    Set Width 1200
    Set Height 800
    Set Theme "Catppuccin Mocha"
    Type "ls -l"
    Enter
    Sleep 500ms
- See the official docs for the full .tape language:
  https://github.com/charmbracelet/vhs

Pro tip: VHS is what powers many of the CodingBooth demo recordings.
EON
