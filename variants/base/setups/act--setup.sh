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
  $0                           # install latest act
  $0 --version 0.2.66          # pin specific version

Notes:
- Installs act to /usr/local/bin/act
- Runs GitHub Actions workflows locally inside Docker; needs dind at runtime
- Upstream release archives use 'x86_64'/'arm64' in the filename
- See: https://github.com/nektos/act
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
  amd64) ACT_ARCH="x86_64" ;;
  arm64) ACT_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/nektos/act/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing act v${VERSION} (${ACT_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/nektos/act/releases/download/v${VERSION}/act_Linux_${ACT_ARCH}.tar.gz" -o "$TMP/act.tar.gz"
tar -xzf "$TMP/act.tar.gz" -C "$TMP"
install -m 755 "$TMP/act" /usr/local/bin/act

echo "✅ act installed."
echo -n "   act → "; act --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Requires Docker (dind--setup.sh) for act to run workflows.
- List jobs:    act -l
- Run workflows: act
- See: https://github.com/nektos/act
EON
