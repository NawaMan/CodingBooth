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
  $0                              # install Elm 0.19.1 (default)
  $0 --version 0.19.1             # pin specific Elm version
  $0 --with-format --with-test    # also install elm-format and elm-test

Notes:
- Installs Elm via npm (requires Node.js — declared via template 'requires').
- Binaries land in /usr/local/lib/node_modules/.bin and are symlinked to /usr/local/bin.
- Pin to a known Elm release; elm 0.19.1 is the de-facto stable.
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

HOME=/root

ELM_DEFAULT_VER="0.19.1"
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
[[ "$ELM_PKG_VER" == "latest" ]] && ELM_PKG_VER=""

echo "📦 Installing elm${ELM_PKG_VER:+@$ELM_PKG_VER} via npm ..."
if [[ -n "$ELM_PKG_VER" ]]; then
  npm install -g "elm@${ELM_PKG_VER}"
else
  npm install -g elm
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
- Elm 0.19.1 is the long-stable release; the language is in maintenance mode.
- Add elm-format/elm-test with --with-format / --with-test.
EON
