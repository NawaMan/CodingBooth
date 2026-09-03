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
  $0                           # install latest k3d
  $0 --version 5.7.5           # pin specific version

Notes:
- Installs k3d (k3s in Docker) to /usr/local/bin/k3d
- Requires Docker (dind--setup.sh) at runtime to create clusters
- See: https://k3d.io
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
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/k3d-io/k3d/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing k3d v${VERSION} (${ARCH}) ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/k3d-io/k3d/releases/download/v${VERSION}/k3d-linux-${ARCH}" -o /usr/local/bin/k3d
chmod +x /usr/local/bin/k3d

install -d /etc/bash_completion.d
k3d completion bash > /etc/bash_completion.d/k3d 2>/dev/null || true

echo "✅ k3d installed."
echo -n "   k3d → "; k3d version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Requires Docker (dind--setup.sh) for k3d to create clusters.
- Create a cluster: k3d cluster create dev
- Delete a cluster: k3d cluster delete dev
- See: https://k3d.io
EON
