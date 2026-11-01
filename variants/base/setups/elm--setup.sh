#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.2.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--with-format] [--with-test]

Examples:
  $0                              # install Elm 0.19.3 (default)
  $0 --version 0.19.2             # pin specific Elm version
  $0 --with-format --with-test    # also install elm-format and elm-test

Notes:
- 0.19.2 and later install the official GitHub linux binaries (x64 and arm).
- 0.19.1 comes prebuilt (sha256-checked) from https://github.com/NawaMan/CodingBoothPrebuilt
  on both CPUs (upstream's 0.19.1 binary is x64 only); npm is the fallback on x64.
- Pin to a known Elm release; elm 0.19.3 is the current stable.
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

HOME=/root

ELM_DEFAULT_VER="0.19.3"
REQ_VER="$ELM_DEFAULT_VER"
WITH_FORMAT=0
WITH_TEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-$ELM_DEFAULT_VER}"; shift ;;
    --with-format) WITH_FORMAT=1; shift ;;
    --with-test) WITH_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v npm >/dev/null 2>&1; then
  echo "❌ elm--setup.sh requires npm (Node.js). Run nodejs--setup.sh first."
  exit 1
fi

ELM_PKG_VER="$REQ_VER"
[[ "$ELM_PKG_VER" == "latest" ]] && ELM_PKG_VER="$ELM_DEFAULT_VER"

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if [[ "$ELM_PKG_VER" == "0.19.2" || "$ELM_PKG_VER" == "0.19.3" ]]; then
  # Official GitHub binaries exist for linux x64 and arm (aarch64) since 0.19.2.
  case "$ARCH" in
    amd64|x86_64) ELM_ASSET="elm-${ELM_PKG_VER}-linux-x64.gz" ;;
    arm64|aarch64) ELM_ASSET="elm-${ELM_PKG_VER}-linux-arm.gz" ;;
    *) echo "❌ Unsupported arch for Elm ${ELM_PKG_VER}: $ARCH"; exit 2 ;;
  esac
  echo "📦 Installing Elm ${ELM_PKG_VER} from GitHub ($ELM_ASSET) ..."
  TMP="$(mktemp -d)"
  curl --retry 5 --retry-delay 3 --retry-all-errors -fL \
    "https://github.com/elm/compiler/releases/download/${ELM_PKG_VER}/${ELM_ASSET}" \
    -o "$TMP/elm.gz"
  gunzip -f "$TMP/elm.gz"
  install -m 0755 "$TMP/elm" /usr/local/bin/elm
  rm -rf "$TMP"
elif [[ "$ELM_PKG_VER" == "0.19.1" ]]; then
  # Upstream's 0.19.1 binary is x64 only; CodingBoothPrebuilt builds it from the
  # tag for both CPUs.
  SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
  if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
  fi
  source "${SETUP_LIBS_DIR}/prebuilt-source.sh"
  TMP="$(mktemp -d)"
  if cb_prebuilt_install elm 0.19.1 native "$TMP/elm"; then
    install -m 0755 "$TMP/elm/elm" /usr/local/bin/elm
  elif [[ "$ARCH" == "amd64" || "$ARCH" == "x86_64" ]]; then
    echo "📦 Installing elm@0.19.1 via npm ..."
    npm install -g elm@0.19.1
  else
    echo "❌ No Elm 0.19.1 for ${ARCH}: the CodingBoothPrebuilt download failed." >&2
    exit 1
  fi
  rm -rf "$TMP"
else
  echo "📦 Installing elm${ELM_PKG_VER:+@$ELM_PKG_VER} via npm ..."
  if [[ -n "$ELM_PKG_VER" ]]; then
    npm install -g "elm@${ELM_PKG_VER}"
  else
    npm install -g elm
  fi
fi

if [[ $WITH_FORMAT -eq 1 ]]; then
  echo "📦 Installing elm-format ..."
  npm install -g elm-format
fi
if [[ $WITH_TEST -eq 1 ]]; then
  echo "📦 Installing elm-test ..."
  npm install -g elm-test
fi

echo "✅ Elm installed."
echo -n "   elm --version → "; elm --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: elm --help
- Init a project: elm init
- Build: elm make src/Main.elm

Notes:
- Elm 0.19.3 is the current stable; 0.19.2 and 0.19.1 remain pin-able.
- Add elm-format/elm-test with --with-format / --with-test.
EON
