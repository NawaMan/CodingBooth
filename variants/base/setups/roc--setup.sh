#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--verify]

Examples:
  $0                       # install default pinned version
  $0 --version latest      # install latest Roc
  $0 --version 0.0.1       # install a specific version
  $0 --verify              # verify SHA256 if checksum is available

Notes:
- Installs to /opt/roc/roc-<ver> and links /opt/roc-stable
- Exposes 'roc' via /usr/local/bin (works in non-login shells)
- Requires amd64 or arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
# Roc uses GitHub release tags as version names. Stable-ish: 'alpha4-rolling'.
# The rolling 'nightly' tag is also accepted (uses date-stamped 'latest' asset).
ROC_DEFAULT_VER="alpha4-rolling"
REQ_VER=""
DO_VERIFY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    --verify) DO_VERIFY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- resolve version ----
ROC_TAG="${REQ_VER:-$ROC_DEFAULT_VER}"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  RARCH="x86_64" ;;
  arm64)  RARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# ---- dirs ----
INSTALL_PARENT=/opt/roc
TARGET_DIR="${INSTALL_PARENT}/roc-${ROC_TAG}"
LINK_DIR=/opt/roc-stable
BIN_DIR=/usr/local/bin

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar gzip coreutils
rm -rf /var/lib/apt/lists/*

# ---- download & install ----
rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR/bin"

# Roc has two asset-naming schemes:
#   nightly tag:        roc_nightly-linux_<arch>-latest.tar.gz
#   named (alphaN-...): roc-linux_<arch>-<tag>.tar.gz
if [[ "$ROC_TAG" == "nightly" ]]; then
  ASSET="roc_nightly-linux_${RARCH}-latest.tar.gz"
else
  ASSET="roc-linux_${RARCH}-${ROC_TAG}.tar.gz"
fi
URL="https://github.com/roc-lang/roc/releases/download/${ROC_TAG}/${ASSET}"
SHA_URL="${URL}.sha256"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Roc ${ROC_TAG} (${RARCH}) ..."
curl -fsSL "$URL" -o "$TMP/$ASSET"

if [[ $DO_VERIFY -eq 1 ]]; then
  if curl -fsSL "$SHA_URL" -o "$TMP/$ASSET.sha256"; then
    echo "🔐 Verifying checksum ..."
    ( cd "$TMP" && sha256sum -c "$ASSET.sha256" )
  else
    echo "⚠️  Checksum file not found for ${ASSET}; skipping verification."
  fi
fi

echo "📦 Installing to ${TARGET_DIR} ..."
tar -xzf "$TMP/$ASSET" -C "$TMP"
# Expect a 'roc' binary in the extracted folder; locate it robustly:
ROC_BIN_PATH="$(find "$TMP" -type f -name 'roc' -perm -111 | head -n1)"
[[ -n "$ROC_BIN_PATH" ]] || { echo "❌ 'roc' binary not found in archive"; exit 1; }
install -Dm755 "$ROC_BIN_PATH" "$TARGET_DIR/bin/roc"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login-shell env ----
cat >/etc/profile.d/99-roc--profile.sh <<'EOF'
# Roc under /opt
export ROC_HOME=/opt/roc-stable
export PATH="$ROC_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-roc--profile.sh

# ---- non-login wrapper ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/rocwrap" <<'EOF'
#!/bin/sh
: "${ROC_HOME:=/opt/roc-stable}"
export ROC_HOME PATH="$ROC_HOME/bin:$PATH"
exec "$ROC_HOME/bin/roc" "$@"
EOF
chmod +x "${BIN_DIR}/rocwrap"
ln -sfn "${BIN_DIR}/rocwrap" "${BIN_DIR}/roc"

# ---- friendly summary ----
echo "✅ Roc ${ROC_TAG} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   roc --version → "; "${BIN_DIR}/roc" --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: roc --help
- Works in login & non-login shells (wrapper primes PATH).

Notes:
- Roc is evolving quickly; use --version latest to stay current, or pin a version for CI.
- If you hit missing platform libs during build, ensure you have a C toolchain (clang/gcc) installed.
EON
