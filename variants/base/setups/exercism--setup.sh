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
  $0                         # install default version
  $0 --version 3.5.5         # pin specific version
  $0 --version latest        # install latest GitHub release

Notes:
- Installs exercism CLI to /usr/local/bin/exercism
- Supports amd64 and arm64
- After install, authenticate with:
    exercism configure --token=<YOUR_TOKEN>
  Get the token from https://exercism.org/settings/api_cli
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="3.5.5"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-3.5.5}"; shift ;;
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
  VERSION=$(curl -fsSL https://api.github.com/repos/exercism/cli/releases/latest | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
else
  VERSION="$REQ_VER"
fi

# ---- install exercism ----
echo "⬇️  Installing exercism CLI v${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl -fsSL "https://github.com/exercism/cli/releases/download/v${VERSION}/exercism-${VERSION}-linux-${ARCH}.tar.gz" -o "${TMP_DIR}/exercism.tar.gz"
tar -xzf "${TMP_DIR}/exercism.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/exercism" /usr/local/bin/exercism
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ exercism CLI installed."
echo -n "   exercism → "; exercism version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Get your API token: https://exercism.org/settings/api_cli
- Configure:  exercism configure --token=<YOUR_TOKEN>
- Browse tracks: https://exercism.org/tracks
- Download an exercise: exercism download --exercise=<slug> --track=<lang>
- Submit a solution:    exercism submit <file>

Notes:
- Exercism is free, open source, and offers mentored feedback on solutions.
- Pairs with any language template in your booth.
- See: https://exercism.org/docs/using/solving-exercises/working-locally
EON
