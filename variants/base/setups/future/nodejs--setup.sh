#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<NODE_VERSION>] [--npm-version <NPM_VERSION>] [--node-version <NODE_VERSION>]

Examples:
  $0                        # Node from NODE_DEFAULT_VERSION, keep bundled npm
  $0 24.9.0                 # Pin Node, keep bundled npm
  $0 24.9.0 --npm-version 11.6.0
  $0 --node-version 24.8.1 --npm-version latest

Env overrides:
  NODE_DEFAULT_VERSION   default Node version (if none passed)  [default: 22.9.0]
  NPM_DEFAULT_VERSION    default npm version (empty/bundled=keep bundled)
USAGE
}

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# Defaults (can be overridden)
NODE_DEFAULT_VERSION="${NODE_DEFAULT_VERSION:-22.9.0}"
NPM_DEFAULT_VERSION="${NPM_DEFAULT_VERSION:-11.6.0}"

NODE_VERSION="$NODE_DEFAULT_VERSION"
NPM_VERSION="$NPM_DEFAULT_VERSION"

# --- Arg parsing (positional node version + flags) ---
POS_NODE_SET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --npm-version)
      shift
      [[ $# -gt 0 ]] || { echo "❌ --npm-version requires a value"; usage; exit 2; }
      NPM_VERSION="$1"; shift
      ;;
    --node-version)
      shift
      [[ $# -gt 0 ]] || { echo "❌ --node-version requires a value"; usage; exit 2; }
      NODE_VERSION="$1"; POS_NODE_SET=1; shift
      ;;
    -h|--help)
      usage; exit 0;;
    *)
      if [[ $POS_NODE_SET -eq 0 ]]; then
        NODE_VERSION="$1"; POS_NODE_SET=1; shift
      else
        echo "❌ Unknown argument: $1"; usage; exit 2
      fi
      ;;
  esac
done

INSTALL_PARENT=/opt/nodejs
TARGET_DIR="${INSTALL_PARENT}/nodejs-${NODE_VERSION}"
LINK_DIR=/opt/nodejs-stable
BASE_URL="https://nodejs.org/dist/v${NODE_VERSION}"

# Determine architecture
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) nodeArch="x64" ;;
  arm64) nodeArch="arm64" ;;
  *)
    echo "❌ Unsupported architecture: $dpkgArch (supported: amd64, arm64)" >&2
    exit 1 ;;
esac

# --- Base tools ---
apt-get update
apt-get install -y --no-install-recommends xz-utils coreutils
rm -rf /var/lib/apt/lists/*

# --- Download tarball + checksums (canonical filename) ---
filename="node-v${NODE_VERSION}-linux-${nodeArch}.tar.xz"
echo "Downloading Node.js v${NODE_VERSION} (${nodeArch})..."
curl -fsSL "${BASE_URL}/${filename}"    -o "/tmp/${filename}"
curl -fsSL "${BASE_URL}/SHASUMS256.txt" -o /tmp/SHASUMS256.txt

# --- Verify checksum ---
echo "Verifying checksum..."
expected="$(grep -E " ${filename}\$" /tmp/SHASUMS256.txt | awk '{print $1}')"
if [ -z "${expected:-}" ]; then
  echo "❌ Checksum entry not found for ${filename} at ${BASE_URL}/SHASUMS256.txt" >&2
  echo "   (This usually means Node ${NODE_VERSION} isn't published for ${nodeArch}.)" >&2
  exit 1
fi
actual="$(sha256sum "/tmp/${filename}" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
  echo "❌ SHA-256 mismatch for ${filename}" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
fi
rm -f /tmp/SHASUMS256.txt

# --- Install into /opt/nodejs/nodejs-<version> ---
rm    -rf  "$TARGET_DIR"
mkdir -p   "$TARGET_DIR"
tar   -xJf "/tmp/${filename}" -C "$TARGET_DIR" --strip-components=1
rm    -f   "/tmp/${filename}"

# --- Stable symlink ---
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- Make binaries available even in non-login shells ---
install -d /usr/local/bin
ln -sfn "$LINK_DIR/bin/node"     /usr/local/bin/node
ln -sfn "$LINK_DIR/bin/npm"      /usr/local/bin/npm
ln -sfn "$LINK_DIR/bin/npx"      /usr/local/bin/npx
ln -sfn "$LINK_DIR/bin/corepack" /usr/local/bin/corepack || true
corepack enable --install-directory /usr/local/bin >/dev/null 2>&1 || true

# --- Optional: set npm version (keeps globals under /opt/nodejs-stable) ---
if [ -n "${NPM_VERSION:-}" ] && [ "${NPM_VERSION}" != "bundled" ]; then
  echo "Upgrading npm to ${NPM_VERSION}..."
  export npm_config_prefix="$LINK_DIR"
  export NPM_CONFIG_PREFIX="$LINK_DIR"
  "$LINK_DIR/bin/npm" install -g "npm@${NPM_VERSION}" --no-fund --no-audit --unsafe-perm
fi

# --- Optional environment for login shells ---
cat >/etc/profile.d/99-node--profile.sh <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export NODE_HOME=/opt/nodejs-stable
export PATH="$NODE_HOME/bin:$PATH"
# ---- end defaults ----
EOF
chmod 0644 /etc/profile.d/99-node--profile.sh

echo "✅ Node.js ${NODE_VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   node: "; /usr/local/bin/node -v
echo -n "   npm:  "; /usr/local/bin/npm  -v
echo -n "   npx:  "; /usr/local/bin/npx  -v
