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
  $0                           # install latest just
  $0 --version 1.58.0          # pin specific version

Notes:
- Installs just to /usr/local/bin/just (single static binary)
- Upstream tags do not include a leading 'v' (e.g. 1.58.0)
- Part of the base image: every variant already has it
- See: https://just.systems
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

JUST_DEFAULT_VER="1.58.0"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) TARGET="x86_64-unknown-linux-musl" ;;
  arm64) TARGET="aarch64-unknown-linux-musl" ;;
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

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/casey/just/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See elixir--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest just release; using ${JUST_DEFAULT_VER}."
    VERSION="$JUST_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

echo "⬇️  Installing just ${VERSION} (${TARGET}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "https://github.com/casey/just/releases/download/${VERSION}/just-${VERSION}-${TARGET}.tar.gz" -o "$TMP/just.tar.gz"
# Extract only the binary. The tarball's completions/ (bash/zsh/fish/...) are
# never used below (bash completion is generated separately via `just
# --completions bash`) and, on arm64 builds cross-built under QEMU, extracting
# them fails the whole build: `tar: completions/just.zsh: Cannot open: Invalid
# argument` — a QEMU-user-emulation/GNU-tar interaction, not a corrupt archive.
tar -xzf "$TMP/just.tar.gz" -C "$TMP" just
install -m 755 "$TMP/just" /usr/local/bin/just

install -d /etc/bash_completion.d
just --completions bash > /etc/bash_completion.d/just 2>/dev/null || true

echo "✅ just installed."
echo -n "   just → "; just --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Create a Justfile:  just --init
- List recipes:       just --list
- Run a recipe:       just <recipe>
- See: https://just.systems
EON
