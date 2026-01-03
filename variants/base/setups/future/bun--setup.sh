#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # install default pinned version (1.1.29)
  $0 --version latest      # latest stable (queried from GitHub)
  $0 --version 1.1.8       # specific version

Notes:
- Installs to /opt/bun/bun-<ver> and links /opt/bun-stable
- /usr/local/bin wrapper ensures bun works in non-login shells
- Also provides 'bunx' (bun x) and 'bunpm' (bun pm) convenience shims
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
BUN_DEFAULT_VER="1.1.29"
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
  VERSION="$BUN_DEFAULT_VER"
elif [[ "$REQ_VER" == "latest" ]]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/oven-sh/bun/releases/latest \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed -E 's/^bun-v?//')"
  [[ -n "$VERSION" ]] || { echo "❌ Failed to resolve latest Bun version"; exit 1; }
else
  VERSION="$REQ_VER"
fi

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  BARCH="x64" ;;
  arm64)  BARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# ---- dirs ----
INSTALL_PARENT=/opt/bun
TARGET_DIR="${INSTALL_PARENT}/bun-${VERSION}"
LINK_DIR=/opt/bun-stable
BIN_DIR=/usr/local/bin

# ---- base tools ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip
rm -rf /var/lib/apt/lists/*

# ---- download & install ----
rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR/bin"

ZIP="bun-linux-${BARCH}.zip"
URL="https://github.com/oven-sh/bun/releases/download/bun-v${VERSION}/${ZIP}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Bun ${VERSION} (${BARCH}) ..."
curl -fsSL "$URL" -o "$TMP/$ZIP"

echo "📦 Installing to ${TARGET_DIR} ..."
unzip -q "$TMP/$ZIP" -d "$TMP"   # extracts a single 'bun' binary in most releases
# Find the binary (name can be 'bun' or 'bun-linux-*'); normalize to 'bun'
BUN_BIN_PATH="$(find "$TMP" -maxdepth 1 -type f -name 'bun*' -printf '%f\n' | head -n1)"
[[ -n "$BUN_BIN_PATH" ]] || { echo "❌ Bun binary not found in archive"; exit 1; }
install -Dm755 "$TMP/$BUN_BIN_PATH" "$TARGET_DIR/bin/bun"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login-shell env ----
cat >/etc/profile.d/99-bun--profile.sh <<'EOF'
# Bun under /opt
export BUN_HOME=/opt/bun-stable
export PATH="$BUN_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-bun--profile.sh

# ---- non-login wrapper + shims ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/bunwrap" <<'EOF'
#!/bin/sh
: "${BUN_HOME:=/opt/bun-stable}"
export BUN_HOME PATH="$BUN_HOME/bin:$PATH"
tool="$(basename "$0")"
case "$tool" in
  bunx) exec "$BUN_HOME/bin/bun" x "$@" ;;
  bunpm) exec "$BUN_HOME/bin/bun" pm "$@" ;;
  *) exec "$BUN_HOME/bin/bun" "$@" ;;
esac
EOF
chmod +x "${BIN_DIR}/bunwrap"
ln -sfn "${BIN_DIR}/bunwrap" "${BIN_DIR}/bun"
ln -sfn "${BIN_DIR}/bunwrap" "${BIN_DIR}/bunx"
ln -sfn "${BIN_DIR}/bunwrap" "${BIN_DIR}/bunpm"

# ---- friendly summary ----
echo "✅ Bun ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   bun --version → "; "${BIN_DIR}/bun" --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: bun --version
- bunx: run npm-style CLIs without installing globally → bunx <pkg> [args]
- bunpm: manage packages (bun pm ...)
- Works in login & non-login shells (wrapper primes PATH).

Tips:
- For project installs: bun install
- For scripts: bun run <script> / bun test
EON
