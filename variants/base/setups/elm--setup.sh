#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--with-format] [--with-test]

Examples:
  $0                              # install Elm 0.19.2 (default)
  $0 --version 0.19.2             # pin specific Elm version
  $0 --with-format --with-test    # also install elm-format and elm-test

Notes:
- 0.19.2 installs the official GitHub linux binaries (x64 and arm).
- 0.19.1 still uses npm, with a community aarch64 binary on arm64.
- Pin to a known Elm release; elm 0.19.2 is the current stable.
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

HOME=/root

ELM_DEFAULT_VER="0.19.2"
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
if [[ "$ELM_PKG_VER" == "0.19.2" ]]; then
  # Official 0.19.2 GitHub binaries exist for linux x64 and arm (aarch64).
  case "$ARCH" in
    amd64|x86_64) ELM_ASSET="elm-0.19.2-linux-x64.gz" ;;
    arm64|aarch64) ELM_ASSET="elm-0.19.2-linux-arm.gz" ;;
    *) echo "❌ Unsupported arch for Elm 0.19.2: $ARCH"; exit 2 ;;
  esac
  echo "📦 Installing Elm 0.19.2 from GitHub ($ELM_ASSET) ..."
  TMP="$(mktemp -d)"
  curl --retry 5 --retry-delay 3 --retry-all-errors -fL \
    "https://github.com/elm/compiler/releases/download/0.19.2/${ELM_ASSET}" \
    -o "$TMP/elm.gz"
  gunzip -f "$TMP/elm.gz"
  install -m 0755 "$TMP/elm" /usr/local/bin/elm
  rm -rf "$TMP"
elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]] && [[ "$ELM_PKG_VER" == "0.19.1" ]]; then
  echo "📦 Installing Elm 0.19.1 (aarch64) via community release ..."
  # The community aarch64 elm binary was built against libffi.so.7 (Ubuntu
  # 20.04). Noble (24.04) only ships libffi8 with incompatible versioned
  # symbols (LIBFFI_CLOSURE_7.0 / LIBFFI_BASE_7.0), so we install the older
  # libffi7 .deb directly from Ubuntu focal's pool. libatomic comes from the
  # current release.
  apt-get update >/dev/null
  apt-get install -y --no-install-recommends libatomic1
  TMP="$(mktemp -d)"
  curl --retry 5 --retry-delay 3 --retry-all-errors -fL http://ports.ubuntu.com/ubuntu-ports/pool/main/libf/libffi/libffi7_3.3-4_arm64.deb \
    -o "$TMP/libffi7.deb"
  dpkg -i "$TMP/libffi7.deb"
  # The official elm npm wrapper resolves to "binary-for-linux-undefined.gz"
  # on arm64 and crashes mid-install. dmy/elm-raspberry-pi only ships an
  # armhf (32-bit) build, which fails on a 64-bit aarch64 container.
  # jbelbruno/Elm_Compiler_0.19.1_for_aarch64 provides a true ARMv8 aarch64
  # build of the elm 0.19.1 compiler.
  curl --retry 5 --retry-delay 3 --retry-all-errors -fL https://github.com/jbelbruno/Elm_Compiler_0.19.1_for_aarch64/releases/download/v0.19.1/elm.gz \
    -o "$TMP/elm.gz"
  gunzip -f "$TMP/elm.gz"
  install -m 0755 "$TMP/elm" /usr/local/bin/elm
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
- Elm 0.19.2 is the current stable; 0.19.1 remains pin-able.
- Add elm-format/elm-test with --with-format / --with-test.
EON
