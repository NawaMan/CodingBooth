#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]
  $0 [<X.Y.Z>|latest]

Examples:
  $0                         # install the current release
  $0 --version 0.2.0         # pin a specific version
  $0 0.2.0                   # same, in the form a Boothfile emits
  $0 --version latest        # install the latest GitHub release

Notes:
- Installs viewmd (MarkDownViewer) to /usr/local/bin/viewmd
- Supports amd64 and arm64
- Part of the base image: every variant already has it
- Checksums are verified against the release's SHA256SUMS
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
VIEWMD_DEFAULT_VER="0.2.0"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"             # no version given means "the current release"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    # `setup viewmd 0.2.0` in a Boothfile compiles to a positional argument, so
    # accept that spelling too rather than failing on the form users will write.
    -*) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
    *) REQ_VER="$1"; shift ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
# The base image already carries curl and ca-certificates; only pay for apt when
# this script is run somewhere leaner.
if ! command -v curl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/NawaMan/MarkDownViewer/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See elixir--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest viewmd release; using ${VIEWMD_DEFAULT_VER}."
    VERSION="$VIEWMD_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install viewmd ----
echo "⬇️  Installing viewmd v${VERSION} (${ARCH}) ..."
BASE_URL="https://github.com/NawaMan/MarkDownViewer/releases/download/v${VERSION}"
ASSET="viewmd-linux-${ARCH}"
TMP_DIR=$(mktemp -d)
curl -fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5 \
  "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/viewmd"

# Verify against the release's SHA256SUMS. A release that predates the checksum
# file leaves nothing to check, so warn rather than fail; a checksum that is
# present and wrong is fatal.
if curl -fsSL "${BASE_URL}/SHA256SUMS" -o "${TMP_DIR}/SHA256SUMS" 2>/dev/null; then
  EXPECTED=$(awk -v asset="$ASSET" '$2 == asset || $2 == "*"asset {print $1}' "${TMP_DIR}/SHA256SUMS" | head -1)
  if [[ -n "$EXPECTED" ]]; then
    ACTUAL=$(sha256sum "${TMP_DIR}/viewmd" | awk '{print $1}')
    if [[ "$EXPECTED" != "$ACTUAL" ]]; then
      echo "❌ Checksum mismatch for ${ASSET}: expected ${EXPECTED}, got ${ACTUAL}"
      rm -rf "${TMP_DIR}"
      exit 1
    fi
    echo "🔒 Checksum verified."
  else
    echo "⚠️  ${ASSET} is not listed in SHA256SUMS; skipping checksum verification."
  fi
else
  echo "⚠️  No SHA256SUMS published for v${VERSION}; skipping checksum verification."
fi

install -m 755 "${TMP_DIR}/viewmd" /usr/local/bin/viewmd
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ viewmd installed."
echo -n "   viewmd → "; viewmd version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Serve the current folder:  viewmd --folder . --md README.md
- Serve in the background:   viewmd --md README.md --daemon
- Reach it from the host:    viewmd --md README.md --expose
- Stop / check it:           viewmd stop   |   viewmd status

Notes:
- viewmd renders a folder of Markdown files in a browser; the default port is 8765.
- --expose calls booth--expose, so the host can open the page without extra wiring.
- See: https://github.com/NawaMan/MarkDownViewer
EON
