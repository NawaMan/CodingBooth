#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--depot </path>] [--verify] [--packages "Pkg1,Pkg2,..."]

Examples:
  $0                                   # default Julia (1.10.4) + shared depot at /opt/julia-depot
  $0 --version latest                  # latest stable from GitHub releases
  $0 --version 1.9.4 --verify          # pin and verify checksum
  $0 --packages "IJulia,DataFrames"    # preinstall packages into the shared depot

Notes:
- Installs to /opt/julia/julia-<ver> and links /opt/julia-stable
- Exposes 'julia' via /usr/local/bin (works in non-login shells)
- Shared depot defaults to /opt/julia-depot (world-writable)
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
JULIA_DEFAULT_VER="1.10.4"   # bump when you want a newer pinned default
REQ_VER=""
DEPOT_DEFAULT="/opt/julia-depot"
DEPOT="$DEPOT_DEFAULT"
DO_VERIFY=0
PKGS_LIST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   shift; REQ_VER="${1:-}"; shift ;;
    --depot)     shift; DEPOT="${1:-$DEPOT_DEFAULT}"; shift ;;
    --verify)    DO_VERIFY=1; shift ;;
    --packages)  shift; PKGS_LIST="${1:-}"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- resolve version (supports 'latest') ----
if [[ -z "$REQ_VER" ]]; then
  VERSION="$JULIA_DEFAULT_VER"
elif [[ "$REQ_VER" == "latest" ]]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/JuliaLang/julia/releases/latest \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
  [[ -n "$VERSION" ]] || { echo "❌ Failed to resolve latest Julia version"; exit 1; }
else
  VERSION="$REQ_VER"
fi

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  JARCH="x86_64";;
  arm64)  JARCH="aarch64";;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# ---- dirs ----
INSTALL_PARENT=/opt/julia
TARGET_DIR="${INSTALL_PARENT}/julia-${VERSION}"
LINK_DIR=/opt/julia-stable
BIN_DIR=/usr/local/bin

# ---- base tools ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends xz-utils coreutils
rm -rf /var/lib/apt/lists/*

# ---- download & install ----
rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR"

TARBALL="julia-${VERSION}-linux-${JARCH}.tar.gz"
BASE="https://github.com/JuliaLang/julia/releases/download/v${VERSION}"
URL="${BASE}/${TARBALL}"
SHAS_URL="${BASE}/SHA256SUMS"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Julia ${VERSION} (${JARCH}) ..."
curl -fsSL "$URL" -o "$TMP/$TARBALL"

if [[ $DO_VERIFY -eq 1 ]]; then
  echo "🔐 Fetching checksums ..."
  curl -fsSL "$SHAS_URL" -o "$TMP/SHA256SUMS"
  echo "   Verifying ${TARBALL} ..."
  ( cd "$TMP" && grep "  ${TARBALL}\$" SHA256SUMS | sha256sum -c - )
fi

echo "📦 Installing to ${TARGET_DIR} ..."
tar -xzf "$TMP/$TARBALL" -C "$TMP"
SRC_DIR="$(find "$TMP" -maxdepth 1 -type d -name "julia-${VERSION}" -print -quit)"
[[ -d "$SRC_DIR" ]] || { echo "❌ Extracted directory not found"; exit 1; }
# Move contents under /opt/julia/julia-<ver>
mv "$SRC_DIR"/* "$TARGET_DIR"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- shared depot (world-writable) ----
mkdir -p "$DEPOT"
chmod -R 0777 "$DEPOT" || true

# ---- login-shell env ----
cat >/etc/profile.d/99-julia--profile.sh <<EOF
# Julia under /opt
export JULIA_HOME=$LINK_DIR
export PATH="\$JULIA_HOME/bin:\$PATH"
# Shared depot so packages are reused across users/CI
export JULIA_DEPOT_PATH=${DEPOT}
EOF
chmod 0644 /etc/profile.d/99-julia--profile.sh

# ---- non-login wrapper ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/juliawrap" <<'EOF'
#!/bin/sh
: "${JULIA_HOME:=/opt/julia-stable}"
: "${JULIA_DEPOT_PATH:=/opt/julia-depot}"
export JULIA_HOME JULIA_DEPOT_PATH PATH="$JULIA_HOME/bin:$PATH"
exec "$JULIA_HOME/bin/julia" "$@"
EOF
chmod +x "${BIN_DIR}/juliawrap"
ln -sfn "${BIN_DIR}/juliawrap" "${BIN_DIR}/julia"

# ---- optional: preinstall packages into shared depot ----
if [[ -n "$PKGS_LIST" ]]; then
  # normalize comma/space separated list to Julia array
  PKGS_JL="$(echo "$PKGS_LIST" | sed 's/,/ /g' | xargs -n1 | awk '{printf "\"%s\",",$0}' | sed 's/,$//')"
  echo "📦 Preinstalling Julia packages: [$PKGS_JL]"
  JULIA_DEPOT_PATH="$DEPOT" "$BIN_DIR/julia" -e "import Pkg; Pkg.update(); Pkg.add.([$PKGS_JL]); Pkg.precompile()"
fi

# ---- friendly summary ----
echo "✅ Julia ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo "   JULIA_DEPOT_PATH = ${DEPOT}"
echo -n "   julia --version → "; "${BIN_DIR}/julia" --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: julia --version
- Works in login & non-login shells (wrapper primes PATH + JULIA_DEPOT_PATH)

Tips:
- Add packages globally (shared depot): julia -e 'using Pkg; Pkg.add("DataFrames"); Pkg.precompile()'
- For Jupyter notebooks: install IJulia (requires Python/Jupyter) → julia -e 'using Pkg; Pkg.add("IJulia")'
- Pin a version in CI by re-running with --version <X.Y.Z> (updates /opt/julia-stable)
EON
