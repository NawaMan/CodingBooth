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
  $0                           # install latest k9s
  $0 --version 0.32.5          # pin specific version

Notes:
- Installs k9s to /usr/local/bin/k9s
- k9s is a TUI - run it interactively in a terminal
- Honors the KUBECONFIG that kubectl uses
- See: https://k9scli.io
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
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing k9s v${VERSION} (${ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/derailed/k9s/releases/download/v${VERSION}/k9s_Linux_${ARCH}.tar.gz" -o "$TMP/k9s.tar.gz"
tar -xzf "$TMP/k9s.tar.gz" -C "$TMP"
install -m 755 "$TMP/k9s" /usr/local/bin/k9s

echo "✅ k9s installed."
echo -n "   k9s → "; k9s version --short 2>/dev/null | head -1 || k9s version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Run: k9s
- Quit: :q  or  Ctrl+C
- Honors $KUBECONFIG / ~/.kube/config (same as kubectl)
- See: https://k9scli.io
EON
