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
  $0                           # install latest direnv
  $0 --version 2.34.0          # pin specific version

Notes:
- Installs direnv to /usr/local/bin/direnv (single static binary)
- Bash hook is wired in via /etc/profile.d so .envrc loads automatically
- See: https://direnv.net
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
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/direnv/direnv/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing direnv v${VERSION} (${ARCH}) ..."
curl -fsSL "https://github.com/direnv/direnv/releases/download/v${VERSION}/direnv.linux-${ARCH}" -o /usr/local/bin/direnv
chmod +x /usr/local/bin/direnv

cat >/etc/profile.d/99-direnv--profile.sh <<'EOF'
# direnv: hook into bash so .envrc files load automatically
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)" 2>/dev/null || true
fi
EOF
chmod 0644 /etc/profile.d/99-direnv--profile.sh

echo "✅ direnv installed."
echo -n "   direnv → "; direnv --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Allow a project's .envrc:   direnv allow
- See active variables:        direnv status
- See: https://direnv.net
EON
