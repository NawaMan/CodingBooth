#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--kind-version <VERSION>] [--kubectl-version <VERSION>|stable]

Examples:
  $0                                    # install latest kind + stable kubectl
  $0 --kind-version 0.27.0              # pin kind version
  $0 --kubectl-version 1.32.0           # pin kubectl version

Notes:
- Installs kind (Kubernetes in Docker) and kubectl
- Requires dind--setup.sh to be run first for Docker-in-Docker support
- kind is installed to /usr/local/bin/kind
- kubectl is installed to /usr/local/bin/kubectl
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
KIND_VERSION="0.27.0"
KUBECTL_VERSION="stable"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind-version) shift; KIND_VERSION="${1:-0.27.0}"; shift ;;
    --kubectl-version) shift; KUBECTL_VERSION="${1:-stable}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping ----
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  KIND_ARCH="amd64"; KUBECTL_ARCH="amd64" ;;
  aarch64) KIND_ARCH="arm64"; KUBECTL_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $ARCH"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

# ---- install kubectl ----
echo "⬇️  Installing kubectl ($KUBECTL_VERSION, $KUBECTL_ARCH) ..."
if [[ "$KUBECTL_VERSION" == "stable" ]]; then
  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
fi
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# ---- install kind ----
echo "⬇️  Installing kind v${KIND_VERSION} ($KIND_ARCH) ..."
curl -fsSL "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-${KIND_ARCH}" -o /usr/local/bin/kind
chmod +x /usr/local/bin/kind

# ---- bash completion ----
install -d /etc/bash_completion.d
kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true
kind completion bash > /etc/bash_completion.d/kind 2>/dev/null || true

# ---- summary ----
echo "✅ kind and kubectl installed."
echo -n "   kind → "; kind version 2>/dev/null || true
echo -n "   kubectl → "; kubectl version --client 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Requires Docker-in-Docker (dind--setup.sh) for kind to work
- Create a cluster: kind create cluster
- Delete a cluster: kind delete cluster
- kubectl configured automatically when cluster is created

Notes:
- kind requires Docker to run Kubernetes nodes as containers
- For persistent storage, consider mounting volumes
- See: https://kind.sigs.k8s.io/
EON
