#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# superfile--setup.sh — Install the superfile terminal file manager (spf) from
# GitHub releases, with a default config that does not check for updates.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest stable superfile
  $0 --version 1.6.0       # pin a release

Notes:
- Installs spf to /usr/local/bin/spf, and links /usr/local/bin/superfile to it
- Checks the release's checksums file before installing, which superfile
  publishes from 1.6.0 on, so 1.6.0 is the oldest release it installs
- Seeds ~/.config/superfile/config.toml at container start when there is none,
  with auto_check_update = false
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
SUPERFILE_FALLBACK_VER="1.6.0"   # used when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

SHARE_DIR="/usr/local/share/superfile"
STARTUP_FILE="/usr/share/startup.d/72-cb-superfile--startup.sh"

# Release assets are named after Debian arches: amd64 / arm64.
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) ARCH="$dpkgArch" ;;
  *) echo "❌ Unsupported arch: ${dpkgArch} (need amd64 or arm64)" >&2; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar coreutils
  rm -rf /var/lib/apt/lists/*
fi

# Tags are vX.Y.Z. A rate-limited API falls back to the pinned release.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/yorukot/superfile/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest superfile release; using ${SUPERFILE_FALLBACK_VER}."
    VERSION="$SUPERFILE_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a superfile version: '${VERSION}' (expected X.Y.Z, for example 1.6.0)" >&2
  exit 2
fi

BASE_URL="https://github.com/yorukot/superfile/releases/download/v${VERSION}"
ASSET="superfile-linux-v${VERSION}-${ARCH}.tar.gz"
SUMS="superfile-v${VERSION}-checksums.txt"

echo "⬇️  Installing superfile ${VERSION} (${ARCH}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ASSET}" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${BASE_URL}/${ASSET}" >&2
  exit 1
fi
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${SUMS}" -o "$TMP/$SUMS"; then
  echo "❌ No ${SUMS} published; refusing to install unverified bytes." >&2
  echo "   superfile publishes a checksums file from 1.6.0 on; pick 1.6.0 or later." >&2
  exit 1
fi

# The checksums file is "<hash>  <asset>" for every asset. Compare ours only.
EXPECTED="$(awk -v a="$ASSET" '$2 == a { print $1; exit }' "$TMP/$SUMS")"
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
  exit 1
fi

# The archive holds ./dist/superfile-linux-vX.Y.Z-<arch>/spf.
tar -xzf "$TMP/$ASSET" -C "$TMP" 2>/dev/null
SRC="$(find "$TMP" -type f -name spf -perm -u+x | head -1)"
if [[ -z "$SRC" ]]; then
  echo "❌ superfile archive did not contain an spf binary" >&2
  exit 1
fi
install -m 755 "$SRC" /usr/local/bin/spf
ln -sfn /usr/local/bin/spf /usr/local/bin/superfile

# ---- default config ----
# superfile reports "missing fields" on a config that lacks any of its keys, so
# the seed is the release's own full default config, with update checks off.
# It is the file superfile writes on its first run, byte for byte.
CONFIG_URL="https://raw.githubusercontent.com/yorukot/superfile/v${VERSION}/src/superfile_config/config.toml"
mkdir -p "$SHARE_DIR"
if curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$CONFIG_URL" -o "$TMP/config.toml" \
   && grep -qE '^auto_check_update = ' "$TMP/config.toml"; then
  sed -E 's/^auto_check_update = .*/auto_check_update = false/' "$TMP/config.toml" > "$SHARE_DIR/config.toml"
  chmod 644 "$SHARE_DIR/config.toml"
else
  rm -f "$SHARE_DIR/config.toml"
  echo "⚠️  Could not fetch superfile's default config; spf will write its own (update checks on)."
fi

# Copies the seed when the user has no config. A config already there, the
# user's own or one from .booth/home, is left alone.
cat > "$STARTUP_FILE" <<'EOF'
#!/usr/bin/env bash
# superfile: seed ~/.config/superfile/config.toml when there is none.
seed="/usr/local/share/superfile/config.toml"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/superfile/config.toml"
if [[ -f "$seed" && ! -e "$conf" ]]; then
  mkdir -p "$(dirname "$conf")" && cp "$seed" "$conf"
fi
EOF
chmod 755 "$STARTUP_FILE"

echo "✅ superfile installed."
echo -n "   spf → "; spf --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Open the file manager:  spf            (or: spf <dir>)
- Show config paths:      spf path-list
- Config file:            ~/.config/superfile/config.toml

Notes:
- Update checks are off in the seeded config (auto_check_update = false).
- Icons use a Nerd Font; the Console UI already has one.
- Docs: https://superfile.dev
EON
