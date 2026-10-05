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
  $0                         # install latest stable kubectl
  $0 --version 1.32.0        # pin specific version
  $0 --no-completion         # skip bash completion setup

Notes:
- Installs kubectl to /usr/local/bin/kubectl
- Supports amd64 and arm64
- Seeds ~/.kube from /etc/cb-home-seed/.kube at startup
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
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://dl.k8s.io/release/stable.txt)
  VERSION="${VERSION#v}"
else
  VERSION="$REQ_VER"
fi

# ---- install kubectl ----
echo "⬇️  Installing kubectl v${VERSION} (${ARCH}) ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://dl.k8s.io/release/v${VERSION}/bin/linux/${ARCH}/kubectl" -o /usr/local/bin/kubectl
chmod 755 /usr/local/bin/kubectl

# ---- bash completion ----
if [[ $WITH_COMPLETION -eq 1 ]]; then
  install -d /etc/bash_completion.d
  kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true
fi

# ---- startup script for credential seeding ----
STARTUP_FILE="/usr/share/startup.d/61-cb-kubectl--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# kubectl startup script
# Copies kubeconfig from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.kube"
KUBE_CONFIG_DIR="$HOME/.kube"

if [[ -d "$CB_SEED_DIR" && ! -d "$KUBE_CONFIG_DIR" ]]; then
    mkdir -p "$KUBE_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$KUBE_CONFIG_DIR/"
    chmod 600 "$KUBE_CONFIG_DIR/config" 2>/dev/null || true
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- friendly summary ----
echo "✅ kubectl installed."
echo -n "   kubectl → "; kubectl version --client 2>/dev/null || true
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: kubectl version --client
- Bash completion: open a new shell or `source /etc/bash_completion.d/kubectl`

Notes:
- kubectl requires a valid kubeconfig to connect to a cluster.
- Credentials are seeded from /etc/cb-home-seed/.kube at startup.
- See: https://kubernetes.io/docs/reference/kubectl/
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse kubeconfig from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Kubernetes credentials (home-seeding: kubeconfig)'
echo '      "-v", "~/.kube:/etc/cb-home-seed/.kube:ro"'
echo '  ]'
echo ""
