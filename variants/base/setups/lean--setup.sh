#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lean--setup.sh — Install Lean 4 (via elan, its toolchain manager) at BUILD time.
# EXPERIMENTAL: new, not yet battle-tested.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <toolchain>] [--elan-version <X.Y.Z>]

Examples:
  $0                              # elan + the stable Lean 4 toolchain
  $0 --version 4.35.0             # pin a release (same as leanprover/lean4:v4.35.0)
  $0 --version v4.36.0-rc1        # a release candidate, as Mathlib often pins
  $0 --version nightly            # the latest nightly

Notes:
- elan is to Lean what rustup is to Rust: it installs toolchains and picks the one a
  project's lean-toolchain file names, downloading it on first use if needed.
- Installs to /opt/elan (ELAN_HOME), writable by the booth user, so a project's own
  lean-toolchain pin can install at run time. The lean+toolchain-file extension bakes
  that pin into the image instead.
- lake (the build tool and package manager) comes with every toolchain.
- See: https://lean-lang.org/install/manual/
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

REQ_VER="stable"
ELAN_VERSION="4.2.4"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)      shift; REQ_VER="${1:-stable}"; shift ;;
    --elan-version) shift; ELAN_VERSION="${1:?--elan-version needs a value}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

LEVEL=60                          # See docs/BOOTH_SETUP.md - LEVEL ordering
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-lean--profile.sh"
export ELAN_HOME="/opt/elan"

# elan release assets use Rust target triples (elan is a rustup fork).
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64)  ASSET_ARCH="x86_64"  ;;
  aarch64|arm64) ASSET_ARCH="aarch64" ;;
  *) echo "❌ Unsupported architecture: ${MACHINE} (need x86_64 or aarch64)" >&2; exit 1 ;;
esac

# Toolchain spelling: channels and full names pass through; a bare version gets the
# leanprover/lean4:v prefix elan expects.
case "$REQ_VER" in
  stable|nightly|beta|*/*|*:*) TOOLCHAIN="$REQ_VER" ;;
  v[0-9]*)                     TOOLCHAIN="leanprover/lean4:${REQ_VER}" ;;
  [0-9]*)                      TOOLCHAIN="leanprover/lean4:v${REQ_VER}" ;;
  *) echo "❌ Not a Lean toolchain: '${REQ_VER}' (stable, nightly, 4.35.0, v4.36.0-rc1, or leanprover/lean4:…)" >&2; exit 2 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
# git: lake fetches every dependency (Mathlib included) with git.
apt-get install -y --no-install-recommends curl ca-certificates tar git
rm -rf /var/lib/apt/lists/*

ASSET="elan-${ASSET_ARCH}-unknown-linux-gnu.tar.gz"
URL="https://github.com/leanprover/elan/releases/download/v${ELAN_VERSION}/${ASSET}"

echo "⬇️  Installing elan v${ELAN_VERSION} (${ASSET_ARCH}) with toolchain ${TOOLCHAIN} ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --proto '=https' --tlsv1.2 --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$ASSET"
tar -xzf "$TMP/$ASSET" -C "$TMP"
"$TMP/elan-init" -y --no-modify-path --default-toolchain "$TOOLCHAIN"

# Writable by the booth user: `elan toolchain install` and a project's lean-toolchain
# pin both write here at run time.
chmod -R a+rwX "$ELAN_HOME"

# elan's proxies dispatch on their own name, so a symlink works from any PATH.
for bin in elan lean lake; do
  ln -sf "${ELAN_HOME}/bin/${bin}" "/usr/local/bin/${bin}"
done

# ---- Profile: login shells. The template mirrors these as image `env` lines,
# since `booth exec` runs with no shell and never reads /etc/profile.d.
cat > "${PROFILE_FILE}" <<'EOF'
# Profile: Lean 4 (elan)
export ELAN_HOME="/opt/elan"
case ":$PATH:" in
  *":/opt/elan/bin:"*) ;;
  *) export PATH="/opt/elan/bin:$PATH";;
esac
EOF
chmod 644 "${PROFILE_FILE}"

echo "✅ Lean installed."
echo -n "   elan → "; "${ELAN_HOME}/bin/elan" --version 2>/dev/null || true
echo -n "   lean → "; "${ELAN_HOME}/bin/lean" --version 2>/dev/null || true
echo -n "   lake → "; "${ELAN_HOME}/bin/lake" --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- New project:  lake new my_proofs && cd my_proofs && lake build
- With Mathlib: lake new my_math math && cd my_math && lake exe cache get && lake build
- Check a file: lake env lean Main.lean
- Toolchains:   elan show   |   elan toolchain list
- Docs:         https://lean-lang.org/documentation/
EON
