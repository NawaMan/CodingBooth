#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--no-completion]

Examples:
  $0                         # install latest stable Helm
  $0 --version 3.16.3        # pin specific version
  $0 --no-completion         # skip bash completion setup

Notes:
- Installs Helm to /usr/local/bin/helm
- Supports amd64 and arm64
- Helm uses kubeconfig from kubectl (no separate credential seeding needed)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
else
  VERSION="$REQ_VER"
fi

# ---- install helm ----
echo "⬇️  Installing Helm v${VERSION} (${ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://get.helm.sh/helm-v${VERSION}-linux-${ARCH}.tar.gz" -o "$TMP/helm.tar.gz"

echo "📦 Extracting ..."
tar -xzf "$TMP/helm.tar.gz" -C "$TMP"
install -m 755 "$TMP/linux-${ARCH}/helm" /usr/local/bin/helm

# ---- bash completion ----
if [[ $WITH_COMPLETION -eq 1 ]]; then
  install -d /etc/bash_completion.d
  helm completion bash > /etc/bash_completion.d/helm 2>/dev/null || true
fi

# ---- friendly summary ----
echo "✅ Helm installed."
echo -n "   helm → "; helm version --short 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: helm version
- Bash completion: open a new shell or `source /etc/bash_completion.d/helm`

Notes:
- Helm uses the same kubeconfig as kubectl.
- No separate credential seeding is needed if kubectl is already configured.
- See: https://helm.sh/docs/
EON
