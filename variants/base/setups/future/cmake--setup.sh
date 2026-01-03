#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--from-apt] [--with-ninja]

Examples:
  $0                              # default prebuilt cmake 3.30.2 (versioned under /opt)
  $0 --version latest             # latest release (prebuilt)
  $0 --from-apt --with-ninja      # Kitware APT repo CMake + Ninja
  $0 --version 3.27.9             # pin specific prebuilt version

Notes:
- Prebuilt mode installs to /opt/cmake/cmake-<ver> and links /opt/cmake-stable
- APT mode installs distro packages and still exposes via /opt/cmake-stable
- /usr/local/bin wrapper ensures cmake/ctest/cpack work in non-login shells
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
CMAKE_DEFAULT_VER="3.30.2"     # bump when you want a newer pinned default
REQ_VER=""
FROM_APT=0
WITH_NINJA=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   shift; REQ_VER="${1:-}"; shift ;;
    --from-apt)  FROM_APT=1; shift ;;
    --with-ninja) WITH_NINJA=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- resolve version (prebuilt mode supports 'latest') ----
if [[ $FROM_APT -eq 1 ]]; then
  VERSION="apt"
else
  if [[ -z "$REQ_VER" ]]; then
    VERSION="$CMAKE_DEFAULT_VER"
  elif [[ "$REQ_VER" == "latest" ]]; then
    VERSION="$(curl -fsSL https://api.github.com/repos/Kitware/CMake/releases/latest \
      | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
    [[ -n "$VERSION" ]] || { echo "❌ Failed to resolve latest CMake version"; exit 1; }
  else
    VERSION="$REQ_VER"
  fi
fi

# ---- common paths ----
INSTALL_PARENT=/opt/cmake
LINK_DIR=/opt/cmake-stable
BIN_DIR=/usr/local/bin

# Clean old shims (idempotent)
for b in cmake ctest cpack; do rm -f "${BIN_DIR}/$b" || true; done

export DEBIAN_FRONTEND=noninteractive

if [[ $FROM_APT -eq 1 ]]; then
  # ===================== APT MODE (Kitware repo) =====================
  # base deps + repo key
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release
  install -d /usr/share/keyrings
  curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc -o /usr/share/keyrings/kitware-archive-keyring.gpg

  . /etc/os-release
  CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  [[ -n "$CODENAME" ]] || { echo "❌ Could not determine distro codename"; exit 1; }

  cat >/etc/apt/sources.list.d/kitware.list <<EOF
deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${CODENAME} main
EOF

  apt-get update
  PKGS=( cmake )
  [[ $WITH_NINJA -eq 1 ]] && PKGS+=( ninja-build )
  apt-get install -y --no-install-recommends "${PKGS[@]}"
  rm -rf /var/lib/apt/lists/*

  SYS_CMAKE="$(command -v cmake)"
  [[ -x "$SYS_CMAKE" ]] || { echo "❌ 'cmake' not found after APT install"; exit 1; }

  # normalize into /opt layout
  TARGET_DIR="${INSTALL_PARENT}/cmake-apt"
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR/bin"
  ln -sfn "$SYS_CMAKE" "$TARGET_DIR/bin/cmake"
  ln -sfn "$(command -v ctest)" "$TARGET_DIR/bin/ctest"
  ln -sfn "$(command -v cpack)" "$TARGET_DIR/bin/cpack"
  ln -sfn "$TARGET_DIR" "$LINK_DIR"

else
  # ===================== PREBUILT TARBALL MODE =====================
  # arch
  dpkgArch="$(dpkg --print-architecture)"
  case "$dpkgArch" in
    amd64)  TARCH="x86_64";;
    arm64)  TARCH="aarch64";;
    *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
  esac

  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar xz-utils
  [[ $WITH_NINJA -eq 1 ]] && apt-get install -y --no-install-recommends ninja-build
  rm -rf /var/lib/apt/lists/*

  TARGET_DIR="${INSTALL_PARENT}/cmake-${VERSION}"
  rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR"

  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  TARBALL="cmake-${VERSION}-linux-${TARCH}.tar.gz"
  URL="https://github.com/Kitware/CMake/releases/download/v${VERSION}/${TARBALL}"

  echo "⬇️  Downloading CMake ${VERSION} (${TARCH}) ..."
  curl -fsSL "$URL" -o "$TMP/$TARBALL"

  echo "📦 Installing to ${TARGET_DIR} ..."
  tar -xzf "$TMP/$TARBALL" -C "$TMP"
  SRC_DIR="$(find "$TMP" -maxdepth 1 -type d -name "cmake-${VERSION}-linux-${TARCH}" -print -quit)"
  [[ -d "$SRC_DIR" ]] || { echo "❌ Extracted directory not found"; exit 1; }
  # move contents (bin/, share/, etc.)
  mv "$SRC_DIR"/* "$TARGET_DIR"

  ln -sfn "$TARGET_DIR" "$LINK_DIR"
fi

# ---- login-shell env ----
cat >/etc/profile.d/99-cmake--profile.sh <<'EOF'
# CMake under /opt
export CMAKE_HOME=/opt/cmake-stable
export PATH="$CMAKE_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-cmake--profile.sh

# ---- non-login wrapper ----
cat >"${BIN_DIR}/cmakewrap" <<'EOF'
#!/bin/sh
: "${CMAKE_HOME:=/opt/cmake-stable}"
export CMAKE_HOME PATH="$CMAKE_HOME/bin:$PATH"
tool="$(basename "$0")"
exec "$CMAKE_HOME/bin/$tool" "$@"
EOF
chmod +x "${BIN_DIR}/cmakewrap"

for t in cmake ctest cpack; do
  ln -sfn "${BIN_DIR}/cmakewrap" "${BIN_DIR}/$t"
done

# ---- friendly summary ----
if [[ $FROM_APT -eq 1 ]]; then
  echo "✅ CMake (Kitware APT) installed; exposed at ${LINK_DIR}."
else
  echo "✅ CMake ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
fi
echo -n "   cmake --version → "; "${BIN_DIR}/cmake" --version | head -n1 || true
if [[ $WITH_NINJA -eq 1 ]]; then
  echo -n "   ninja --version → "; command -v ninja >/dev/null && ninja --version | head -n1 || echo "ninja not found"
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: cmake --version
- Works in login & non-login shells (wrapper primes PATH).
- APT mode keeps system packages; tarball mode is fully /opt versioned.

Tips:
- With Ninja: cmake -G Ninja -S . -B build && cmake --build build
- Want GUI? Install `cmake-qt-gui` in APT mode or use a Qt-enabled build.
EON
