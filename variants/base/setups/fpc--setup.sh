#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Free Pascal Compiler (FPC) setup script

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <x.y.z>] [--with-lazarus|--no-lazarus]

Examples:
  $0                        # default FPC from apt
  $0 --version 3.2.2        # specific version (from apt if available)
  $0 --with-lazarus         # also install Lazarus IDE (requires desktop)

Notes:
- Installs Free Pascal Compiler via apt packages
- Creates /opt/fpc-stable link for consistency
- Lazarus IDE is optional and large (needs X11/desktop)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "Run as root (use sudo)"; exit 1; }

# ---- defaults / args ----
FPC_VER=""
WITH_LAZARUS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)      shift; FPC_VER="${1:-}"; shift ;;
    --with-lazarus) WITH_LAZARUS=1; shift ;;
    --no-lazarus)   WITH_LAZARUS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# "latest" means "whatever the distro ships" — same as passing nothing. Without
# this it would reach apt as the literal package pin "fpc=latest*".
[[ "$FPC_VER" == "latest" ]] && FPC_VER=""

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update

# ---- install FPC ----
echo "Installing Free Pascal Compiler ..."
if [[ -n "$FPC_VER" ]]; then
  # Try to install specific version if apt supports it
  apt-get install -y --no-install-recommends "fpc=${FPC_VER}*" 2>/dev/null || \
    apt-get install -y --no-install-recommends fpc
else
  apt-get install -y --no-install-recommends fpc
fi

# ---- Lazarus IDE (optional) ----
if [[ $WITH_LAZARUS -eq 1 ]]; then
  echo "Installing Lazarus IDE ..."
  apt-get install -y --no-install-recommends lazarus
fi

rm -rf /var/lib/apt/lists/*

# ---- detect installed version ----
FPC_BIN="$(command -v fpc)"
[[ -x "$FPC_BIN" ]] || { echo "FPC not found after installation"; exit 1; }

FPC_ACTUAL_VER="$("$FPC_BIN" -iV 2>/dev/null || echo "unknown")"

# ---- normalize into /opt layout ----
INSTALL_PARENT=/opt/fpc
TARGET_DIR="${INSTALL_PARENT}/fpc-${FPC_ACTUAL_VER}"
LINK_DIR=/opt/fpc-stable
BIN_DIR=/usr/local/bin

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR/bin"

# Link the system binaries into /opt layout
for bin in fpc fpc-${FPC_ACTUAL_VER} ppcx64 ppcarm64 fp fpcmake fppkg instantfpc; do
  if command -v "$bin" >/dev/null 2>&1; then
    ln -sfn "$(command -v "$bin")" "$TARGET_DIR/bin/$bin"
  fi
done

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login-shell env ----
cat >/etc/profile.d/61-cb-fpc--profile.sh <<'EOF'
# Free Pascal under /opt
export FPC_HOME=/opt/fpc-stable
export PATH="$FPC_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/61-cb-fpc--profile.sh

# ---- non-login wrapper ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/fpcwrap" <<'EOF'
#!/bin/sh
: "${FPC_HOME:=/opt/fpc-stable}"
export PATH="$FPC_HOME/bin:$PATH"
tool="$(basename "$0")"
# FPC binaries are in /usr/bin, just exec directly
exec "$(command -v "$tool")" "$@"
EOF
chmod +x "${BIN_DIR}/fpcwrap"

# We don't need wrappers for FPC since apt installs to /usr/bin
# but we can add convenience symlinks
ln -sfn "$FPC_BIN" "${BIN_DIR}/fpc" 2>/dev/null || true

# ---- summary ----
echo "Free Pascal ${FPC_ACTUAL_VER} installed."
echo -n "   fpc: "; fpc -iV 2>&1 || true
if [[ $WITH_LAZARUS -eq 1 ]]; then
  echo "   Lazarus IDE installed (run: lazarus-ide or startlazarus)"
fi

cat <<'EON'
Ready to use:
- fpc --version
- fpc hello.pas -o hello    # compile Pascal source
- fp                        # text-mode IDE
- lazarus-ide               # GUI IDE (if installed)
EON
