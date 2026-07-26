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
  $0                           # install latest fzf
  $0 --version 0.55.0          # pin specific version

Notes:
- Installs fzf to /usr/local/bin/fzf (single static binary)
- Bash key bindings & completion are placed under /etc/profile.d
- See: https://github.com/junegunn/fzf
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
  VERSION=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing fzf v${VERSION} (${ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${VERSION}/fzf-${VERSION}-linux_${ARCH}.tar.gz" -o "$TMP/fzf.tar.gz"
tar -xzf "$TMP/fzf.tar.gz" -C "$TMP"
install -m 755 "$TMP/fzf" /usr/local/bin/fzf

cat >/etc/profile.d/99-fzf--profile.sh <<'EOF'
# fzf bash keybindings & completion (best-effort: only if files exist on PATH)
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash 2>/dev/null)" || true
fi
EOF
chmod 0644 /etc/profile.d/99-fzf--profile.sh

echo "✅ fzf installed."
echo -n "   fzf → "; fzf --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Pipe anything: ls | fzf
- History search: Ctrl-R (in interactive bash, after profile is sourced)
- File search:    Ctrl-T
- See: https://github.com/junegunn/fzf
EON
