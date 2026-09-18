#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION]

Arguments:
  VERSION  CUDA Toolkit version to install, as "MAJOR-MINOR" (e.g. 13-4),
           or "latest" for whatever cuda-toolkit currently resolves to.
           Default: latest

Examples:
  $0            # install the newest cuda-toolkit
  $0 13-4       # pin CUDA Toolkit 13.4.x

⚠️  READ BEFORE SELECTING THIS: this installs the CUDA *compiler and
libraries* (nvcc, headers, runtime libs) into the image -- it does
NOT install a GPU driver, and it cannot make a GPU appear in a booth
that doesn't have one. Using the GPU at runtime needs, on the HOST
running Docker (not in this container):
  1. An NVIDIA GPU with a driver installed
  2. The NVIDIA Container Toolkit (nvidia-ctk / nvidia-container-toolkit)
     configured for Docker
Without both, \`docker run --gpus all\` fails outright -- the booth
will not start, not just "run without GPU support". Only select this
template for a project you know will run on a GPU-configured host.
See: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/
     https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

VERSION="${1:-latest}"

# NVIDIA's repo layout distinguishes amd64 (standard x86_64 servers) from two
# different arm64 flavors: Jetson boards (their own "arm64" tree, a different
# rootfs entirely, not this Ubuntu image) and server-class Arm64 with a
# datacenter GPU (their "sbsa" tree, e.g. Grace/Graviton hosts) -- this is
# always the latter, never the Jetson one, in a generic Docker container.
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) REPO_ARCH="x86_64" ;;
  arm64) REPO_ARCH="sbsa" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

REPO="ubuntu2404"
KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${REPO}/${REPO_ARCH}/cuda-keyring_1.1-1_all.deb"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

echo "⬇️  Adding NVIDIA CUDA apt repo (${REPO}/${REPO_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$KEYRING_URL" -o "$TMP/cuda-keyring.deb"
dpkg -i "$TMP/cuda-keyring.deb"

PKG="cuda-toolkit"
if [[ "$VERSION" != "latest" ]]; then
  PKG="cuda-toolkit-${VERSION}"
fi

echo "⬇️  Installing ${PKG} ..."
apt-get update
apt-get install -y --no-install-recommends "$PKG"
rm -rf /var/lib/apt/lists/*

echo "✅ ${PKG} installed."
echo -n "   nvcc → "; nvcc --version 2>/dev/null | tail -1 || true

cat <<'EON'
ℹ️ Ready to use (once the HOST has a GPU + NVIDIA Container Toolkit):
- Compile:  nvcc my_kernel.cu -o my_kernel
- Check the GPU is visible inside the booth: nvidia-smi
- No driver is installed here on purpose -- it comes from the host via
  `docker run --gpus all`, which this template's run-args already add.
EON
