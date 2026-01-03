#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # install default pinned version (1.46.3)
  $0 --version latest      # latest stable from GitHub
  $0 --version 1.45.5      # specific version

Notes:
- Installs to /opt/deno/deno-<ver> and links /opt/deno-stable
- /usr/local/bin wrapper ensures deno works in non-login shells
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
DENO_DEFAULT_VER="1.46.3"
REQ_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- resolve version ----
if [[ -z "$REQ_VER" ]]; then
  VERSION="$DENO_DEFAULT_VER"
elif [[ "$REQ_VER" == "latest" ]]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/denoland/deno/releases/latest \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
  [[ -n "$VERSION" ]] || { echo "❌ Failed to resolve latest Deno version"; exit 1; }
else
  VERSION="$REQ_VER"
fi

# ---- arch ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  DARCH="x86_64-unknown-linux-gnu";;
  arm64)  DARCH="aarch64-unknown-linux-gnu";;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# ---- dirs ----
INSTALL_PARENT=/opt/deno
TARGET_DIR="${INSTALL_PARENT}/deno-${VERSION}"
LINK_DIR=/opt/deno-stable
BIN_DIR=/usr/local/bin

# ---- base tools ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip
rm -rf /var/lib/apt/lists/*

# ---- download + install ----
rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR/bin"

TARBALL="deno-${DARCH}.zip"
URL="https://github.com/denoland/deno/releases/download/v${VERSION}/${TARBALL}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Deno ${VERSION} (${DARCH}) ..."
curl -fsSL "$URL" -o "$TMP/$TARBALL"

echo "📦 Installing to ${TARGET_DIR} ..."
unzip -q "$TMP/$TARBALL" -d "$TARGET_DIR/bin"

ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login-shell env ----
cat >/etc/profile.d/99-deno--profile.sh <<'EOF'
# Deno under /opt
export DENO_HOME=/opt/deno-stable
export PATH="$DENO_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-deno--profile.sh

# ---- non-login wrapper ----
cat >"${BIN_DIR}/denowrap" <<'EOF'
#!/bin/sh
: "${DENO_HOME:=/opt/deno-stable}"
export DENO_HOME PATH="$DENO_HOME/bin:$PATH"
exec "$DENO_HOME/bin/deno" "$@"
EOF
chmod +x "${BIN_DIR}/denowrap"
ln -sfn "${BIN_DIR}/denowrap" "${BIN_DIR}/deno"

# ---- friendly summary ----
echo "✅ Deno ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   deno --version → "; "${BIN_DIR}/deno" --version | head -n1 || true

cat <<'EON'
ℹ️ Ready to use:
- Try: deno run https://deno.land/std/examples/welcome.ts
- Works in login & non-login shells (wrapper primes PATH).
EON
