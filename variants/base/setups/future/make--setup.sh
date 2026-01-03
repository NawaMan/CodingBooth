#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y>] [--from-apt] [--with-docs]

Examples:
  $0                         # build GNU Make 4.4.1 from source into /opt/make
  $0 --version 4.3           # build a specific version
  $0 --from-apt              # install distro's make package quickly
  $0 --version 4.4.1 --with-docs  # also install manpages (source build)

Notes:
- Source build installs to /opt/make/make-<ver> and links /opt/make-stable
- Adds /usr/local/bin/make wrapper so it works in non-login shells
- APT mode installs distro's 'make' and points /opt/make-stable to it
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
MAKE_DEFAULT_VER="4.4.1"   # update when you want a newer pinned default
REQ_VER=""
FROM_APT=0
WITH_DOCS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   shift; REQ_VER="${1:-}"; shift ;;
    --from-apt)  FROM_APT=1; shift ;;
    --with-docs) WITH_DOCS=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

VERSION="${REQ_VER:-$MAKE_DEFAULT_VER}"

INSTALL_PARENT=/opt/make
TARGET_DIR="${INSTALL_PARENT}/make-${VERSION}"
LINK_DIR=/opt/make-stable
BIN_DIR=/usr/local/bin

# Clean old shims (idempotent)
for b in make gmake; do rm -f "${BIN_DIR}/$b" || true; done

export DEBIAN_FRONTEND=noninteractive

if [[ $FROM_APT -eq 1 ]]; then
  # ---------- APT MODE ----------
  apt-get update
  apt-get install -y --no-install-recommends make
  rm -rf /var/lib/apt/lists/*

  # Point /opt/make-stable at the system make prefix (wrap just the binary)
  SYS_MAKE="$(command -v make)"
  [[ -x "$SYS_MAKE" ]] || { echo "❌ 'make' not found after APT install"; exit 1; }

  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR/bin"
  ln -sfn "$SYS_MAKE" "$TARGET_DIR/bin/make"
  # gmake symlink for BSD compatibility
  ln -sfn "$SYS_MAKE" "$TARGET_DIR/bin/gmake"

  ln -sfn "$TARGET_DIR" "$LINK_DIR"

else
  # ---------- SOURCE BUILD MODE ----------
  apt-get update
  apt-get install -y --no-install-recommends \
    build-essential curl ca-certificates tar xz-utils \
    libgmp-dev  # (autoconf uses it on some distros; harmless)
  # docs require help2man & groff (only if requested)
  if [[ $WITH_DOCS -eq 1 ]]; then
    apt-get install -y --no-install-recommends help2man groff
  fi
  rm -rf /var/lib/apt/lists/*

  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  TARBALL="make-${VERSION}.tar.gz"
  URL="https://ftp.gnu.org/gnu/make/${TARBALL}"
  ALT_URL="https://ftpmirror.gnu.org/make/${TARBALL}"

  echo "⬇️  Downloading GNU Make ${VERSION} ..."
  if ! curl -fsSL "$URL" -o "$TMP/$TARBALL"; then
    echo "   Primary mirror failed, trying fallback mirror..."
    curl -fsSL "$ALT_URL" -o "$TMP/$TARBALL"
  fi

  echo "📦 Building GNU Make ${VERSION} ..."
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"

  tar -xzf "$TMP/$TARBALL" -f "$TMP/$TARBALL" -C "$TMP"
  SRC_DIR="$(find "$TMP" -maxdepth 1 -type d -name "make-*")"
  cd "$SRC_DIR"

  # Configure with prefix to our /opt target
  ./configure --prefix="$TARGET_DIR" >/dev/null
  make -j"$(nproc)" >/dev/null

  if [[ $WITH_DOCS -eq 1 ]]; then
    make -j"$(nproc)" install >/dev/null
  else
    # install binaries only (avoid manpages)
    make install-binPROGRAMS install-dist_docDATA >/dev/null 2>&1 || true
    make install >/dev/null
  fi

  # BSD-friendly alias
  ln -sfn "$TARGET_DIR/bin/make" "$TARGET_DIR/bin/gmake"

  # Stable link
  ln -sfn "$TARGET_DIR" "$LINK_DIR"
fi

# ---- login-shell env (just PATH) ----
cat >/etc/profile.d/99-make--profile.sh <<'EOF'
# GNU Make under /opt
export MAKE_HOME=/opt/make-stable
export PATH="$MAKE_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-make--profile.sh

# ---- non-login wrapper ----
cat >"${BIN_DIR}/makewrap" <<'EOF'
#!/bin/sh
: "${MAKE_HOME:=/opt/make-stable}"
export MAKE_HOME PATH="$MAKE_HOME/bin:$PATH"
tool="$(basename "$0")"
exec "$MAKE_HOME/bin/$tool" "$@"
EOF
chmod +x "${BIN_DIR}/makewrap"

# Expose make & gmake via wrapper
ln -sfn "${BIN_DIR}/makewrap" "${BIN_DIR}/make"
ln -sfn "${BIN_DIR}/makewrap" "${BIN_DIR}/gmake"

# ---- friendly summary ----
echo "✅ GNU Make installed."
if [[ $FROM_APT -eq 1 ]]; then
  echo "   Mode: APT (system package wrapped under $LINK_DIR)"
else
  echo "   Mode: Source build ${VERSION} → ${TARGET_DIR}"
fi
echo "   MAKE_HOME -> ${LINK_DIR}"
echo -n "   make --version → "; "${BIN_DIR}/make" --version | head -n1 || true

cat <<'EON'
ℹ️ Ready to use:
- Try: make --version
- Works in login & non-login shells (wrapper primes PATH).

Notes:
- Source builds live under /opt/make/make-<ver>; re-run with --version to switch.
- APT mode uses the distro's make but still exposes it via /opt/make-stable.
- A BSD-friendly 'gmake' alias is provided.
EON
