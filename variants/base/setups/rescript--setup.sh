#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # install ReScript 11.1.4 (default)
  $0 --version 11.1.4      # pin specific version
  $0 --version latest      # latest from npm

Notes:
- Installs ReScript globally via npm (requires Node.js — declared via template 'requires').
- 'rescript' binary becomes available globally.
- ReScript is the typed-language compiling to JS; modern successor to ReasonML.
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

HOME=/root

RESCRIPT_DEFAULT_VER="11.1.4"   # kept as the --version fallback
REQ_VER="latest"                # no version given means "the current release";
                                # npm's own 'latest' dist-tag decides, and for
                                # rescript that tag points at a stable release.

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-$RESCRIPT_DEFAULT_VER}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v npm >/dev/null 2>&1; then
  echo "❌ rescript--setup.sh requires npm (Node.js). Run nodejs--setup.sh first."
  exit 1
fi

RESCRIPT_PKG_VER="$REQ_VER"
[[ "$RESCRIPT_PKG_VER" == "latest" ]] && RESCRIPT_PKG_VER=""

echo "📦 Installing rescript${RESCRIPT_PKG_VER:+@$RESCRIPT_PKG_VER} via npm ..."
if [[ -n "$RESCRIPT_PKG_VER" ]]; then
  npm install -g "rescript@${RESCRIPT_PKG_VER}"
else
  npm install -g rescript
fi

echo "✅ ReScript installed."
echo -n "   rescript -v → "; rescript -v 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: rescript -h
- Init a project: npm create rescript-app@latest my-app
- Build: rescript build

Notes:
- For React projects with ReScript, see https://rescript-lang.org/
EON
