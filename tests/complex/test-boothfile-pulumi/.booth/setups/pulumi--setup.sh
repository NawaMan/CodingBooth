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
  $0                         # install latest Pulumi
  $0 --version 3.136.1       # pin specific version
  $0 --no-completion         # skip bash completion setup

Notes:
- Installs Pulumi binaries to /usr/local/bin/
- Supports amd64 and arm64
- Downloads from official Pulumi GitHub releases
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
  amd64) ARCH="x64" ;;
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
  echo "🔍 Resolving latest Pulumi version ..."
  VERSION="$(curl -fsSL https://www.pulumi.com/latest-version)"
  if [[ -z "$VERSION" ]]; then
    echo "❌ Failed to resolve latest Pulumi version"; exit 1
  fi
  echo "   Latest version: ${VERSION}"
else
  if [[ ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like X.Y.Z (e.g., 3.136.1)"; exit 2
  fi
  VERSION="$REQ_VER"
fi

# ---- download and install ----
TAR_URL="https://get.pulumi.com/releases/sdk/pulumi-v${VERSION}-linux-${ARCH}.tar.gz"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Pulumi ${VERSION} (${ARCH}) ..."
curl -fsSL "$TAR_URL" -o "$TMP/pulumi.tar.gz"

echo "📦 Extracting to /opt/pulumi ..."
rm -rf /opt/pulumi
mkdir -p /opt/pulumi
tar -xzf "$TMP/pulumi.tar.gz" -C /opt/pulumi --strip-components=1

echo "🛠  Symlinking binaries to /usr/local/bin/ ..."
for bin in /opt/pulumi/*; do
  if [[ -f "$bin" && -x "$bin" ]]; then
    ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
  fi
done

# ---- bash completion ----
if [[ $WITH_COMPLETION -eq 1 ]]; then
  install -d /etc/bash_completion.d
  pulumi gen-completion bash > /etc/bash_completion.d/pulumi
fi

# ---- friendly summary ----
INSTALLED_VER="$(pulumi version)"
echo "✅ Pulumi installed: ${INSTALLED_VER}"
echo "   Binaries: /opt/pulumi/"
echo "   Symlinks: /usr/local/bin/"

cat <<'EON'
ℹ️ Ready to use:
- Try: pulumi version
- Common commands:
    pulumi new        # create a new project
    pulumi up         # deploy infrastructure
    pulumi preview    # preview changes
    pulumi destroy    # tear down infrastructure
    pulumi stack ls   # list stacks

Notes:
- This script installs the official Pulumi SDK from get.pulumi.com.
- Cloud provider credentials are managed per provider (e.g., AWS, GCP, Azure).
- To update: re-run with --version <new>.
EON
