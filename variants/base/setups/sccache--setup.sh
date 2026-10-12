#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install sccache ${SCCACHE_DEFAULT_VER:-(pinned default)}
  $0 --version latest        # newest release
  $0 --version 0.18.0        # pin specific version

Notes:
- Installs sccache to /usr/local/bin/sccache (the static musl build)
- Supports amd64 and arm64
- Only installs the binary: cargo uses it once RUSTC_WRAPPER=sccache is set,
  which the rust+sccache extension does on the container environment
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
SCCACHE_DEFAULT_VER="0.17.0"   # used as-is, and as the fallback when 'latest' cannot be resolved
REQ_VER="$SCCACHE_DEFAULT_VER"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-$SCCACHE_DEFAULT_VER}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64" ;;
  arm64) ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# The base image already carries curl, tar, and ca-certificates; only pay for
# apt when this script is run somewhere leaner.
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/mozilla/sccache/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See elixir--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest sccache release; using ${SCCACHE_DEFAULT_VER}."
    VERSION="$SCCACHE_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install sccache ----
echo "⬇️  Installing sccache v${VERSION} (${ARCH}) ..."
NAME="sccache-v${VERSION}-${ARCH}-unknown-linux-musl"
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/mozilla/sccache/releases/download/v${VERSION}/${NAME}.tar.gz" -o "${TMP_DIR}/sccache.tar.gz"
tar -xzf "${TMP_DIR}/sccache.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/${NAME}/sccache" /usr/local/bin/sccache
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ sccache installed."
echo -n "   sccache → "; sccache --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- cargo build                 # compiled crates are cached when RUSTC_WRAPPER=sccache
- sccache --show-stats        # cache hits and misses since the server started
- sccache --zero-stats        # reset the counters

Notes:
- The cache lives in SCCACHE_DIR (default ~/.cache/sccache), capped by SCCACHE_CACHE_SIZE (default 10G).
- Incrementally compiled crates (your own workspace members in a debug build) are not cached;
  dependencies are, which is where most of the build time goes.
- See: https://github.com/mozilla/sccache
EON
