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
  $0                           # install latest dive
  $0 --version 0.12.0          # pin specific version

Notes:
- Installs dive to /usr/local/bin/dive
- TUI for inspecting Docker image layers; needs Docker at runtime
- See: https://github.com/wagoodman/dive
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
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/wagoodman/dive/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing dive v${VERSION} (${ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/wagoodman/dive/releases/download/v${VERSION}/dive_${VERSION}_linux_${ARCH}.tar.gz" -o "$TMP/dive.tar.gz"
tar -xzf "$TMP/dive.tar.gz" -C "$TMP"
install -m 755 "$TMP/dive" /usr/local/bin/dive

echo "✅ dive installed."
echo -n "   dive → "; dive --version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Inspect an image:  dive <image>:<tag>
- Build & inspect:   dive build -t myimg .
- Requires Docker (dind--setup.sh) at runtime to read images.
- See: https://github.com/wagoodman/dive
EON
