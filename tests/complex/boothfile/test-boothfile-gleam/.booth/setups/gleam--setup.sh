#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# gleam--setup.sh — Install the Gleam compiler from GitHub releases
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                           # install the latest stable Gleam
  $0 --version 1.18.1          # pin a specific version
  $0 --version 1.19.0-rc2      # a release candidate, only when asked for by name

Notes:
- Installs the single static (musl) gleam binary to /usr/local/bin/gleam, SHA256-checked
  against the checksum published next to each release asset.
- gleam compiles to Erlang; running code (gleam run / gleam test) needs Erlang/OTP.
  If erl is not on PATH, erlang--setup.sh is run first (which also brings rebar3).
- The JavaScript target (gleam run --target javascript) additionally needs Node.js.
- See: https://gleam.run/getting-started/installing/
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

# Gleam release assets use Rust target triples: x86_64/aarch64-unknown-linux-musl
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64)  ASSET_ARCH="x86_64"  ;;
  aarch64|arm64) ASSET_ARCH="aarch64" ;;
  *) echo "❌ Unsupported architecture: ${MACHINE} (need x86_64 or aarch64)" >&2; exit 1 ;;
esac

# --- Erlang/OTP: gleam is only a compiler, the BEAM runs the result ---
if ! command -v erl >/dev/null 2>&1; then
  echo "⚠️  Erlang/OTP not found. Installing automatically..."
  erlang--setup.sh
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar
rm -rf /var/lib/apt/lists/*

# Known-good pin when the GitHub API is rate-limited.
FALLBACK_VERSION="1.18.1"
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$'

if [[ "$REQ_VER" == "latest" ]]; then
  # /releases/latest skips prereleases, so this never picks an -rc.
  # Match the tag_name *key* only — never sed the whole JSON line (minified
  # payloads put everything on one line; greedy sed grabs the last quote).
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/gleam-lang/gleam/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest Gleam from GitHub (got '${VERSION:-empty}'); falling back to v${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a Gleam version: '${VERSION}' (expected X.Y.Z or X.Y.Z-rcN)" >&2
  exit 2
fi

ASSET="gleam-v${VERSION}-${ASSET_ARCH}-unknown-linux-musl.tar.gz"
URL="https://github.com/gleam-lang/gleam/releases/download/v${VERSION}/${ASSET}"

echo "⬇️  Installing Gleam v${VERSION} (${ASSET_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL"        -o "$TMP/$ASSET"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL.sha256" -o "$TMP/$ASSET.sha256"

# The .sha256 file is "<hash> *<asset>"; compare the hash only.
EXPECTED="$(awk '{print $1}' "$TMP/$ASSET.sha256")"
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{print $1}')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
  exit 1
fi

tar -xzf "$TMP/$ASSET" -C "$TMP" gleam
install -m 755 "$TMP/gleam" /usr/local/bin/gleam

echo "✅ Gleam installed."
echo -n "   gleam → "; gleam --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- New project:   gleam new my_app && cd my_app
- Run / test:    gleam run    |    gleam test
- Add a package: gleam add wisp
- Format:        gleam format
- JS target:     gleam run --target javascript   (needs Node.js — select the nodejs template)
- Docs:          https://tour.gleam.run/
EON
