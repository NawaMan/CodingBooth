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
  $0                         # install latest Goose CLI
  $0 --version 1.43.0        # pin a specific version

Notes:
- Installs Goose (Block / AAIF), an open extensible AI agent CLI (code + MCP + automation).
- Binary name: goose
- Config: ~/.config/goose/config.yaml
- Secrets often live alongside config under ~/.config/goose/ (or env provider keys).
- See: https://goose-docs.ai  and  https://github.com/aaif-goose/goose
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
  amd64) GOOSE_ARCH="x86_64" ;;
  arm64) GOOSE_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar bzip2
rm -rf /var/lib/apt/lists/*

REPO="aaif-goose/goose"
if [[ "$REQ_VER" == "latest" ]]; then
  # Prefer the stable tag pointer when available; else latest release.
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"v?([^"]+)".*/\1/')
  RELEASE_TAG="v${VERSION}"
  # If a floating "stable" release exists, use it for the download URL.
  if curl -fsSL --head "https://github.com/${REPO}/releases/download/stable/download_cli.sh" >/dev/null 2>&1; then
    # Still pin reported version from latest for profile text; download via stable assets.
    USE_STABLE_TAG=1
  else
    USE_STABLE_TAG=0
  fi
else
  VERSION="${REQ_VER#v}"
  RELEASE_TAG="v${VERSION}"
  USE_STABLE_TAG=0
fi

if [[ -z "$VERSION" ]]; then
  echo "❌ Failed to resolve Goose version" >&2
  exit 1
fi

# Ubuntu/glibc booths use the gnu (standard) build.
FILE="goose-${GOOSE_ARCH}-unknown-linux-gnu.tar.bz2"
if [[ "$USE_STABLE_TAG" -eq 1 ]]; then
  URL="https://github.com/${REPO}/releases/download/stable/${FILE}"
else
  URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${FILE}"
fi

echo "⬇️  Installing Goose CLI v${VERSION} (${FILE}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 30 \
  -o "$TMP/goose.tar.bz2" "$URL"
tar -xjf "$TMP/goose.tar.bz2" -C "$TMP"

BIN=""
if [[ -f "$TMP/goose" ]]; then
  BIN="$TMP/goose"
else
  BIN="$(find "$TMP" -type f -name goose | head -1 || true)"
fi
if [[ -z "$BIN" || ! -f "$BIN" ]]; then
  echo "❌ Could not find goose binary in archive" >&2
  exit 1
fi
chmod +x "$BIN"
if ! "$BIN" --version </dev/null >/dev/null 2>&1 && ! "$BIN" -V </dev/null >/dev/null 2>&1; then
  # Some builds only respond to subcommands; still install if the binary is executable.
  echo "⚠️  goose --version failed; installing binary anyway."
fi
install -m 755 "$BIN" /usr/local/bin/goose

STARTUP_FILE="/usr/share/startup.d/70-cb-goose--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-goose--profile.sh"

cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Goose startup — credential/config seed handled by booth-entry smart_copy.
mkdir -p "$HOME/.config/goose"
EOF
chmod 755 "${STARTUP_FILE}"

cat > "${PROFILE_FILE}" <<EOF
# Profile: Goose CLI v${VERSION}
#   goose                    # interactive agent session
#   goose configure          # set provider / model / extensions
#
# Config: ~/.config/goose/config.yaml
# Provider keys via env (OPENAI_API_KEY, ANTHROPIC_API_KEY, …) or goose configure.
# Docs: https://goose-docs.ai
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "✅ Goose CLI installed."
echo "   Version: ${VERSION}"
echo "   Binary:  /usr/local/bin/goose"
echo "   Startup: ${STARTUP_FILE}"
echo ""
echo "=== Credential Seeding ==="
echo '  run-args = ['
echo '      "-v", "~/.config/goose/config.yaml:/etc/cb-home-seed/.config/goose/config.yaml:ro",'
echo '      "-v", "~/.config/goose/secrets.yaml:/etc/cb-home-seed/.config/goose/secrets.yaml:ro"'
echo '  ]'
echo ""
