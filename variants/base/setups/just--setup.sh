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
  $0                           # install latest just
  $0 --version 1.36.0          # pin specific version

Notes:
- Installs just to /usr/local/bin/just (single static binary)
- Upstream tags do not include a leading 'v' (e.g. 1.36.0)
- See: https://just.systems
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
  amd64) TARGET="x86_64-unknown-linux-musl" ;;
  arm64) TARGET="aarch64-unknown-linux-musl" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/casey/just/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing just ${VERSION} (${TARGET}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/casey/just/releases/download/${VERSION}/just-${VERSION}-${TARGET}.tar.gz" -o "$TMP/just.tar.gz"
tar -xzf "$TMP/just.tar.gz" -C "$TMP"
install -m 755 "$TMP/just" /usr/local/bin/just

install -d /etc/bash_completion.d
just --completions bash > /etc/bash_completion.d/just 2>/dev/null || true

echo "✅ just installed."
echo -n "   just → "; just --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Create a Justfile:  just --init
- List recipes:       just --list
- Run a recipe:       just <recipe>
- See: https://just.systems
EON
