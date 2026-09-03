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
  $0                           # install latest stern
  $0 --version 1.31.0          # pin specific version

Notes:
- Installs stern to /usr/local/bin/stern
- Multi-pod log tailing for Kubernetes; honors KUBECONFIG
- See: https://github.com/stern/stern
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
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/stern/stern/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing stern v${VERSION} (${ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/stern/stern/releases/download/v${VERSION}/stern_${VERSION}_linux_${ARCH}.tar.gz" -o "$TMP/stern.tar.gz"
tar -xzf "$TMP/stern.tar.gz" -C "$TMP"
install -m 755 "$TMP/stern" /usr/local/bin/stern

install -d /etc/bash_completion.d
stern --completion bash > /etc/bash_completion.d/stern 2>/dev/null || true

echo "✅ stern installed."
echo -n "   stern → "; stern --version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Tail one app:    stern myapp
- Tail a label:    stern -l app=myapp
- Tail multiple namespaces: stern --all-namespaces myapp
- Honors $KUBECONFIG / ~/.kube/config (same as kubectl).
- See: https://github.com/stern/stern
EON
