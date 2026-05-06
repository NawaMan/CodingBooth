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
ROC_DEFAULT_VER="0.0.1"   # update when you want a newer pinned default
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

# ---- resolve version (supports 'latest') ----
if [[ -z "$REQ_VER" ]]; then
  VERSION="$ROC_DEFAULT_VER"
elif [[ "$REQ_VER" == "latest" ]]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/roc-lang/roc/releases/latest \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed -E 's/^v//')"
  [[ -n "$VERSION" ]] || { echo "❌ Failed to resolve latest Roc version"; exit 1; }
else
  VERSION="$REQ_VER"
fi

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  RARCH="x86_64" ;;
  arm64)  RARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# ---- dirs ----
INSTALL_PARENT=/opt/roc
TARGET_DIR="${INSTALL_PARENT}/roc-${VERSION}"
LINK_DIR=/opt/roc-stable
BIN_DIR=/usr/local/bin

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar gzip coreutils
rm -rf /var/lib/apt/lists/*

# ---- download & install ----
rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR/bin"

ASSET="roc_nightly-linux-${RARCH}.tar.gz"
# Roc releases currently use nightly naming for the binary artifact; keep this pattern.
URL="https://github.com/roc-lang/roc/releases/download/v${VERSION}/${ASSET}"
SHA_URL="${URL}.sha256"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Roc ${VERSION} (${RARCH}) ..."
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
echo "✅ Roc ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   roc --version → "; "${BIN_DIR}/roc" --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: roc --help
- Works in login & non-login shells (wrapper primes PATH).

Notes:
- Roc is evolving quickly; use --version latest to stay current, or pin a version for CI.
- If you hit missing platform libs during build, ensure you have a C toolchain (clang/gcc) installed.
EON
