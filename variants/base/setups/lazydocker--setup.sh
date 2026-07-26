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
  $0                         # install latest stable lazydocker
  $0 --version 0.23.3        # pin specific version

Notes:
- Installs lazydocker to /usr/local/bin/lazydocker
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64" ;;
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
  VERSION=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
else
  VERSION="$REQ_VER"
fi

# ---- install lazydocker ----
echo "⬇️  Installing lazydocker v${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl -fsSL "https://github.com/jesseduffield/lazydocker/releases/download/v${VERSION}/lazydocker_${VERSION}_Linux_${ARCH}.tar.gz" -o "${TMP_DIR}/lazydocker.tar.gz"
tar -xzf "${TMP_DIR}/lazydocker.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/lazydocker" /usr/local/bin/lazydocker
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ lazydocker installed."
echo -n "   lazydocker → "; lazydocker --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: lazydocker
- Run to manage Docker containers, images, and volumes with a terminal UI

Notes:
- lazydocker is a simple terminal UI for Docker.
- See: https://github.com/jesseduffield/lazydocker
EON
