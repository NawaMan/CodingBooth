#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# goose-lang--setup.sh — Install the Goose programming language (aardappel/goose) from GitHub releases
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <YYYY.N>|latest] [--no-cc]

Examples:
  $0                           # install the latest Goose release
  $0 --version 2026.2          # pin a release (the v prefix is optional)
  $0 --no-cc                   # skip gcc: in-process runs only, no 'goose-lang build'

Notes:
- The command is goose-lang, NOT goose: the Goose AI agent (goose--setup.sh) owns that name,
  and both can be installed in the same booth.
- Installs the release archive (compiler, stdlib, bundled TinyCC, samples, docs, VS Code
  extension) to /usr/local/goose-lang-<version>, linked at /usr/local/goose-lang-current.
  The compiler finds its stdlib beside its real path, so /usr/local/bin/goose-lang is a symlink.
- Installs libc6-dev, which in-process runs need, and gcc, which 'goose-lang build' needs.
- x86_64: upstream's goose-v<version>-linux-x64.tar.gz, checked against GitHub's asset digest.
- arm64: Goose publishes no linux arm64 build, so it comes prebuilt (sha256-checked) from
  https://github.com/NawaMan/CodingBoothPrebuilt, laid out like upstream's x64 one. A version
  not prebuilt (yet) is built from source the way upstream builds its release (CMake, a C++20
  compiler and SDL3's build libraries, which stay installed; several minutes).
- See: https://aardappel.github.io/goose/
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
WITH_CC=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --no-cc)   WITH_CC=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64)  ASSET_ARCH="x64" ;;
  aarch64|arm64) ASSET_ARCH="arm64" ;;
  *) echo "❌ Unsupported architecture: ${MACHINE} (need x86_64 or arm64)" >&2; exit 1 ;;
esac

PKGS=(curl ca-certificates tar libc6-dev)
[[ $WITH_CC -eq 1 ]] && PKGS+=(gcc)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${PKGS[@]}"
rm -rf /var/lib/apt/lists/*

# Known-good pin when the GitHub API is rate-limited.
FALLBACK_VERSION="2026.3"
VERSION_RE='^[0-9]{4}\.[0-9]+(\.[0-9]+)?$'

if [[ "$REQ_VER" == "latest" ]]; then
  # Match the tag_name *key* only — never sed the whole JSON line (minified
  # payloads put everything on one line; greedy sed grabs the last quote).
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/aardappel/goose/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest Goose from GitHub (got '${VERSION:-empty}'); falling back to v${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a Goose version: '${VERSION}' (expected YYYY.N, e.g. 2026.3)" >&2
  exit 2
fi

TARGET_DIR="/usr/local/goose-lang-${VERSION}"
LINK_DIR="/usr/local/goose-lang-current"

echo "⬇️  Installing Goose v${VERSION} (linux-${ASSET_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# x86_64: upstream's release archive.
install_upstream() {
  local ASSET="goose-v${VERSION}-linux-x64.tar.gz"
  local URL="https://github.com/aardappel/goose/releases/download/v${VERSION}/${ASSET}"
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$ASSET"

  # Goose publishes no checksum file; GitHub records a sha256 digest per release asset.
  # Each asset's "name" precedes its "digest" in the API payload. When the API is
  # unreachable (rate limit) the download is kept, with a warning.
  local EXPECTED ACTUAL
  EXPECTED=$(curl -fsSL --retry 3 --retry-delay 3 --retry-all-errors \
               "https://api.github.com/repos/aardappel/goose/releases/tags/v${VERSION}" 2>/dev/null \
             | grep -oE '"(name|digest)"[[:space:]]*:[[:space:]]*"[^"]*"' \
             | sed -E 's/^"([a-z]+)"[[:space:]]*:[[:space:]]*"([^"]*)"$/\1 \2/' \
             | awk -v asset="$ASSET" '$1=="name"{hit=($2==asset); next} hit && $1=="digest"{sub(/^sha256:/,"",$2); print $2; exit}' || true)
  ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{print $1}')"
  if [[ -z "$EXPECTED" ]]; then
    echo "⚠️  No sha256 digest available for ${ASSET} from the GitHub API; not verified." >&2
  elif [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
    exit 1
  fi
  mkdir -p "$TARGET_DIR"
  tar -xzf "$TMP/$ASSET" -C "$TARGET_DIR" --strip-components=1
}

# arm64 without a prebuilt: build the release tag the way upstream's release workflow does,
# with the blessed packages compiled in (its packaging requires them) and the libraries
# SDL3, which the gfx package builds, needs (upstream's list).
build_from_source() {
  echo "ℹ️  Goose v${VERSION}: no prebuilt arm64 build; building from source..."
  apt-get update
  apt-get install -y --no-install-recommends build-essential cmake git python3 \
    libasound2-dev libpulse-dev libaudio-dev libfribidi-dev libjack-dev libsndio-dev \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev \
    libxss-dev libxtst-dev libxkbcommon-dev libdrm-dev libgbm-dev libdbus-1-dev \
    libibus-1.0-dev libudev-dev libthai-dev libpipewire-0.3-dev libwayland-dev \
    libdecor-0-dev liburing-dev
  rm -rf /var/lib/apt/lists/*
  git clone -q --depth 1 --branch "v${VERSION}" https://github.com/aardappel/goose "$TMP/goose"
  (
    cd "$TMP/goose"
    cmake -B build -DCMAKE_BUILD_TYPE=Release -DGOOSE_BUILTIN_LIBS=all "-DGOOSE_VERSION=v${VERSION}"
    cmake --build build --config Release --parallel
    python3 scripts/package_release.py --build build --config Release --out "$TARGET_DIR"
  )
}

rm -rf "$TARGET_DIR"
if [[ "$ASSET_ARCH" == x64 ]]; then
  install_upstream
else
  SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
  if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
  fi
  source "${SETUP_LIBS_DIR}/prebuilt-source.sh"
  cb_prebuilt_install goose-lang "$VERSION" native "$TARGET_DIR" || build_from_source
fi
chmod -R a+rX "$TARGET_DIR"
ln -sfn "$TARGET_DIR" "$LINK_DIR"
ln -sfn "$LINK_DIR/goose" /usr/local/bin/goose-lang

echo "✅ Goose installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   goose-lang → "; goose-lang version 2>/dev/null || true
[[ $WITH_CC -eq 1 ]] || echo "   gcc skipped (--no-cc): 'goose-lang build' needs a C compiler (cc, gcc or clang)."

cat <<'EON'
ℹ️ Ready to use:
- Run a program:     goose-lang hello.goose        (in-process, via the bundled TinyCC)
- Typecheck only:    goose-lang check hello.goose
- Build executable:  goose-lang build hello.goose && ./hello
- Samples / docs:    /usr/local/goose-lang-current/samples  |  https://aardappel.github.io/goose/
- Language server:   goose-lang lsp
EON
