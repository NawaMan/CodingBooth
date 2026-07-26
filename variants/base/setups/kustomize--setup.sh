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
  $0                           # install latest kustomize
  $0 --version 5.4.3           # pin specific version

Notes:
- Installs kustomize to /usr/local/bin/kustomize
- Upstream tags use the form 'kustomize/vX.Y.Z' because the repo also
  ships kyaml and cmd/config; this script picks the kustomize/* line.
- See: https://kustomize.io
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
  VERSION=$(curl -fsSL "https://api.github.com/repos/kubernetes-sigs/kustomize/releases?per_page=30" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"kustomize/v[^"]+"' | head -1 | sed -E 's|.*"kustomize/v([^"]+)".*|\1|')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing kustomize v${VERSION} (${ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${VERSION}/kustomize_v${VERSION}_linux_${ARCH}.tar.gz" -o "$TMP/kustomize.tar.gz"
tar -xzf "$TMP/kustomize.tar.gz" -C "$TMP"
install -m 755 "$TMP/kustomize" /usr/local/bin/kustomize

install -d /etc/bash_completion.d
kustomize completion bash > /etc/bash_completion.d/kustomize 2>/dev/null || true

echo "✅ kustomize installed."
echo -n "   kustomize → "; kustomize version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Build:   kustomize build ./overlays/dev
- Pipe to kubectl: kustomize build ./overlays/dev | kubectl apply -f -
- Edit:    kustomize edit set image my-app=my-app:1.2.3
- See: https://kustomize.io
EON
