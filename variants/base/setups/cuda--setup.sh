#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.1

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
  $0 13-4       # pin CUDA Toolkit 13.4.x (the ubuntu2604 repo has 13-3 and up)

⚠️  READ BEFORE SELECTING THIS: this installs the CUDA *compiler and
libraries* (nvcc, headers, runtime libs) into the image -- it does
NOT install a GPU driver, and it cannot make a GPU appear in a booth
that doesn't have one. Using the GPU at runtime needs, on the HOST
running Docker (not in this container):
  1. An NVIDIA GPU with a driver installed
  2. The NVIDIA Container Toolkit (nvidia-ctk / nvidia-container-toolkit)
     configured for Docker
Without both, \`docker run --gpus all\` fails outright -- the booth
will not start, not just "run without GPU support".

If the host driver is older than this toolkit (nvidia-smi shows the
newest CUDA the driver supports), compile with \`nvcc -arch=native\`:
a default build targets an older GPU generation, so a newer GPU runs
its PTX through the driver's JIT, which an older driver cannot do
("the provided PTX was compiled with an unsupported toolchain"). Only select this
template for a project you know will run on a GPU-configured host.
See: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/
     https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

PROFILE_FILE="/etc/profile.d/62-cb-cuda--profile.sh"

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

# NVIDIA publishes one repo per Ubuntu release; it must match the base image
# (26.04), or apt mixes another release's libraries into this one.
REPO="ubuntu2604"
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

# ---- profile script ----
# NVIDIA's packages install under /usr/local/cuda and put nothing on PATH.
cat >"${PROFILE_FILE}" <<'EOF'
# ---- CUDA environment (safe to source multiple times) ----
case ":$PATH:" in
  *":/usr/local/cuda/bin:"*) : ;;
  *) export PATH="/usr/local/cuda/bin:$PATH" ;;
esac
# ---- end CUDA defaults ----
EOF
chmod 0644 "${PROFILE_FILE}"

echo "✅ ${PKG} installed."
echo -n "   nvcc → "; /usr/local/cuda/bin/nvcc --version 2>/dev/null | tail -1 || true
echo "   Profile: ${PROFILE_FILE}"

cat <<'EON'
ℹ️ Ready to use (once the HOST has a GPU + NVIDIA Container Toolkit):
- Compile:  nvcc -arch=native my_kernel.cu -o my_kernel
  (-arch=native builds for this GPU; without it, a host driver older
  than this toolkit fails at run time with "unsupported toolchain")
- Check the GPU is visible inside the booth: nvidia-smi
- No driver is installed here on purpose -- it comes from the host via
  `docker run --gpus all`, which this template's run-args already add.
EON
