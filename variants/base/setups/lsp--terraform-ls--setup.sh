#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--terraform-ls--setup.sh — Install terraform-ls, HashiCorp's Terraform language server.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest terraform-ls
  $0 --version 0.39.0      # pin a release

Notes:
- Installs to /usr/local/bin/terraform-ls from releases.hashicorp.com
- Checks the download against HashiCorp's published SHA256SUMS
- Does not install terraform itself
- Supports amd64 and arm64
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

TFLS_FALLBACK_VER="0.39.0"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
  amd64|x86_64)  ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch (need amd64 or arm64)" >&2; exit 1 ;;
esac

if ! command -v unzip >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends unzip
  rm -rf /var/lib/apt/lists/*
fi

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 3 --retry-delay 2 https://checkpoint-api.hashicorp.com/v1/check/terraform-ls 2>/dev/null \
            | jq -r '.current_version // empty' 2>/dev/null || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest terraform-ls release; using ${TFLS_FALLBACK_VER}."
    VERSION="$TFLS_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi
if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a terraform-ls version: '${VERSION}' (expected X.Y.Z, for example 0.39.0)" >&2
  exit 2
fi

BASE="https://releases.hashicorp.com/terraform-ls/${VERSION}"
ZIP="terraform-ls_${VERSION}_linux_${ARCH}.zip"
echo "⬇️  Installing terraform-ls ${VERSION} (${ARCH}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE}/${ZIP}" -o "$TMP/$ZIP"; then
  echo "❌ Download failed: ${BASE}/${ZIP}" >&2
  exit 1
fi
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE}/terraform-ls_${VERSION}_SHA256SUMS" -o "$TMP/SUMS"; then
  echo "❌ No SHA256SUMS published for terraform-ls ${VERSION}; refusing to install unverified bytes." >&2
  exit 1
fi
EXPECTED="$(awk -v f="$ZIP" '$2 == f { print $1 }' "$TMP/SUMS")"
ACTUAL="$(sha256sum "$TMP/$ZIP" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ SHA256 mismatch for ${ZIP} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
  exit 1
fi

unzip -q -o "$TMP/$ZIP" terraform-ls -d "$TMP"
install -m 755 "$TMP/terraform-ls" /usr/local/bin/terraform-ls

echo "✅ terraform-ls installed."
echo -n "   terraform-ls → "; terraform-ls version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: terraform-ls serve
- Fresh, Helix, and neovim+lsp pick it up for .tf and .tfvars files

Notes:
- Validation and completion need the terraform binary too (select the terraform template).
- See: https://github.com/hashicorp/terraform-ls
EON
