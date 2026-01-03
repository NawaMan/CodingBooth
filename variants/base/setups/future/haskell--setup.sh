#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--ghc-version <ver>|recommended] [--cabal-version <ver>|recommended]
     [--with-stack|--no-stack] [--with-hls|--no-hls]

Examples:
  $0                                  # GHC=recommended, Cabal=recommended, +Stack, +HLS
  $0 --ghc-version 9.8.2              # pin GHC
  $0 --cabal-version 3.12.1.0         # pin Cabal
  $0 --no-stack --no-hls              # only GHC + Cabal

Notes:
- Installs under /opt/haskell/haskell-<GHCVER> and links /opt/haskell-stable
- Binaries work in login & non-login shells via /usr/local/bin wrappers
USAGE
}

# --- root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# --- defaults ---
GHC_VERSION="recommended"
CABAL_VERSION="recommended"
WITH_STACK=1
WITH_HLS=1

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ghc-version)        shift; GHC_VERSION="${1:-recommended}"; shift ;;
    --cabal-version)      shift; CABAL_VERSION="${1:-recommended}"; shift ;;
    --with-stack)         WITH_STACK=1; shift ;;
    --no-stack)           WITH_STACK=0; shift ;;
    --with-hls)           WITH_HLS=1; shift ;;
    --no-hls)             WITH_HLS=0; shift ;;
    -h|--help)            usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# --- arch guard (Ubuntu/Debian) ---
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)" >&2; exit 1 ;;
esac

# --- locations ---
INSTALL_PARENT=/opt/haskell
# Use a readable folder name even if user asks for "recommended"
GHC_LABEL="${GHC_VERSION/recommended/recommended}"
TARGET_DIR="${INSTALL_PARENT}/haskell-${GHC_LABEL}"
LINK_DIR=/opt/haskell-stable

# Tell ghcup to install inside TARGET_DIR (no ~/.ghcup)
export GHCUP_INSTALL_BASE_PREFIX="${TARGET_DIR}"

# --- base packages (runtime + build deps ghc often needs) ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates xz-utils gzip git make build-essential \
  libgmp-dev zlib1g-dev libtinfo6
rm -rf /var/lib/apt/lists/*

# --- clean any old wrappers that might be in PATH early ---
for b in ghc ghci runghc cabal stack haskell-language-server ghcup; do
  rm -f "/usr/local/bin/$b" || true
done

# --- prepare target dir fresh/idempotent ---
rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"

# --- noninteractive ghcup bootstrap vars ---
export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
export BOOTSTRAP_HASKELL_MINIMAL=0         # we want Cabal too
# GHC/Cabal versions
export BOOTSTRAP_HASKELL_GHC_VERSION="${GHC_VERSION}"
export BOOTSTRAP_HASKELL_CABAL_VERSION="${CABAL_VERSION}"
# Stack & HLS toggles
if [ "$WITH_STACK" -eq 1 ]; then
  unset BOOTSTRAP_HASKELL_INSTALL_NO_STACK
else
  export BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1
fi
if [ "$WITH_HLS" -eq 1 ]; then
  export BOOTSTRAP_HASKELL_INSTALL_HLS=1
else
  export BOOTSTRAP_HASKELL_INSTALL_HLS=0
fi
# Don’t touch user rc files; we’ll manage PATH ourselves
export GHCUP_SKIP_UPDATE_CHECK=1

echo "Installing Haskell via ghcup:"
echo "  GHC=${GHC_VERSION}, Cabal=${CABAL_VERSION}, Stack=$([ $WITH_STACK -eq 1 ] && echo yes || echo no), HLS=$([ $WITH_HLS -eq 1 ] && echo yes || echo no)"

# --- run ghcup bootstrap (no shell rc changes) ---
curl -fsSL https://get-ghcup.haskell.org | bash -s -- -d

# --- point to installed ghcup/bin for this shell ---
export PATH="${TARGET_DIR}/.ghcup/bin:${TARGET_DIR}/.cabal/bin:${PATH}"

# --- if pinned versions were requested, ensure they are the active ones ---
# (When "recommended", ghcup already set suitable defaults.)
if [ "$GHC_VERSION" != "recommended" ]; then
  "${TARGET_DIR}/.ghcup/bin/ghcup" set ghc "${GHC_VERSION}" || true
fi
if [ "$CABAL_VERSION" != "recommended" ]; then
  "${TARGET_DIR}/.ghcup/bin/ghcup" set cabal "${CABAL_VERSION}" || true
fi

# --- figure out actual versions chosen ---
ACTUAL_GHC="$("${TARGET_DIR}/.ghcup/bin/ghcup" whereis ghc --numeric 2>/dev/null || true)"
ACTUAL_CABAL="$("${TARGET_DIR}/.ghcup/bin/ghcup" whereis cabal --numeric 2>/dev/null || true)"
ACTUAL_STACK=""
if [ "$WITH_STACK" -eq 1 ]; then
  ACTUAL_STACK="$("${TARGET_DIR}/.ghcup/bin/stack" --numeric-version 2>/dev/null || true)"
fi
ACTUAL_HLS=""
if [ "$WITH_HLS" -eq 1 ]; then
  ACTUAL_HLS="$("${TARGET_DIR}/.ghcup/bin/haskell-language-server" --numeric-version 2>/dev/null || true)"
fi

# --- stable link ---
ln -sfn "${TARGET_DIR}" "${LINK_DIR}"

# --- env for login shells (POSIX) ---
cat >/etc/profile.d/99-haskell--profile.sh <<'EOF'
# Haskell toolchain (ghcup-managed) under /opt
export HASKELL_HOME=/opt/haskell-stable
export PATH="$HASKELL_HOME/.ghcup/bin:$HASKELL_HOME/.cabal/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-haskell--profile.sh

# --- fish & nushell autoloads ---
install -d /etc/fish/conf.d
cat >/etc/fish/conf.d/haskell.fish <<'EOF'
set -gx HASKELL_HOME /opt/haskell-stable
if test -d $HASKELL_HOME/.ghcup/bin
  fish_add_path -g $HASKELL_HOME/.ghcup/bin
end
if test -d $HASKELL_HOME/.cabal/bin
  fish_add_path -g $HASKELL_HOME/.cabal/bin
end
EOF
chmod 0644 /etc/fish/conf.d/haskell.fish

install -d /etc/nu
cat >/etc/nu/haskell.nu <<'EOF'
$env.HASKELL_HOME = "/opt/haskell-stable"
let ghcup = ($env.HASKELL_HOME | path join ".ghcup" "bin")
let cabal = ($env.HASKELL_HOME | path join ".cabal" "bin")
if ($ghcup | path exists) { $env.PATH = ($ghcup | path add $env.PATH) }
if ($cabal | path exists) { $env.PATH = ($cabal | path add $env.PATH) }
EOF
chmod 0644 /etc/nu/haskell.nu

# --- multi-call wrapper for non-login shells ---
install -d /usr/local/bin
cat >/usr/local/bin/hswrap <<'EOF'
#!/bin/sh
# Ensure /opt Haskell toolchain is used even in non-login shells
HASKELL_HOME="${HASKELL_HOME:-/opt/haskell-stable}"
export PATH="$HASKELL_HOME/.ghcup/bin:$HASKELL_HOME/.cabal/bin:$PATH"
tool="$(basename "$0")"
exec "$(command -v "$tool")" "$@"
EOF
chmod +x /usr/local/bin/hswrap

# Symlink common tools to the wrapper (so PATH is primed before lookup)
for t in ghc ghci runghc cabal stack haskell-language-server ghcup; do
  ln -sfn /usr/local/bin/hswrap "/usr/local/bin/$t"
done

# --- summary ---
echo "✅ Haskell installed in ${TARGET_DIR} (linked at ${LINK_DIR})"
if [ -n "$ACTUAL_GHC" ];   then echo "   ghc:    $ACTUAL_GHC"; fi
if [ -n "$ACTUAL_CABAL" ]; then echo "   cabal:  $ACTUAL_CABAL"; fi
if [ -n "$ACTUAL_STACK" ]; then echo "   stack:  $ACTUAL_STACK"; fi
if [ -n "$ACTUAL_HLS" ];   then echo "   hls:    $ACTUAL_HLS"; fi

# Sanity (won't fail the script if absent)
echo -n "   ghc --version:    "; /usr/local/bin/ghc --version 2>/dev/null || true
echo -n "   cabal --version:  "; /usr/local/bin/cabal --version 2>/dev/null || true
if [ $WITH_STACK -eq 1 ]; then
  echo -n "   stack --version:  "; /usr/local/bin/stack --version 2>/dev/null || true
fi
if [ $WITH_HLS -eq 1 ]; then
  echo -n "   hls --version:    "; /usr/local/bin/haskell-language-server --version 2>/dev/null || true
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: ghc --version && cabal --version
- Works in login & non-login shells (wrappers export PATH automatically).
- To change versions later, use: ghcup tui   # or: ghcup set ghc <ver>, ghcup install ghc <ver>
EON
