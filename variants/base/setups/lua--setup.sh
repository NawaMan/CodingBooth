#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<LUA_VERSION>] [--lua-version <ver>] [--luarocks-version <ver>]
     [--with-luajit|--no-luajit]

Examples:
  $0                                # Lua 5.4.7 + LuaRocks 3.11.1
  $0 5.3.6                          # Pin Lua 5.3.6
  $0 --lua-version 5.4.6 --luarocks-version 3.11.1
  $0 --with-luajit                  # Also install LuaJIT from apt (system path)

Notes:
- Installs Lua under /opt/lua/lua-<version> and links /opt/lua-stable
- Installs LuaRocks bound to that Lua
- Exposes lua/luac/luarocks via /usr/local/bin with a wrapper (non-login shells work)
- Optional: installs LuaJIT via apt for convenience (binary at /usr/bin/luajit)
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults ---
LUA_DEFAULT_VERSION="5.4.7"
LUAROCKS_DEFAULT_VERSION="3.11.1"
WITH_LUAJIT=0

# --- parse args ---
LUA_VERSION_INPUT="${1:-}"
if [[ "$LUA_VERSION_INPUT" =~ ^- ]]; then LUA_VERSION_INPUT=""; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lua-version) shift; LUA_VERSION_INPUT="${1:-}"; shift ;;
    --luarocks-version) shift; LUAROCKS_VERSION_INPUT="${1:-}"; shift ;;
    --with-luajit) WITH_LUAJIT=1; shift ;;
    --no-luajit)   WITH_LUAJIT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$LUA_VERSION_INPUT" ]]; then
        LUA_VERSION_INPUT="$1"; shift
      else
        echo "❌ Unknown arg: $1"; usage; exit 2
      fi
      ;;
  esac
done

LUA_VERSION="${LUA_VERSION_INPUT:-$LUA_DEFAULT_VERSION}"
LUAROCKS_VERSION="${LUAROCKS_VERSION_INPUT:-$LUAROCKS_DEFAULT_VERSION}"

# --- arch guard (Ubuntu/Debian) ---
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# --- locations ---
INSTALL_PARENT=/opt/lua
TARGET_DIR="${INSTALL_PARENT}/lua-${LUA_VERSION}"
LINK_DIR=/opt/lua-stable

# --- URLs ---
LUA_TGZ="https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz"
LUAROCKS_TGZ="https://luarocks.github.io/luarocks/releases/luarocks-${LUAROCKS_VERSION}.tar.gz"

# --- base deps ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential curl ca-certificates xz-utils tar \
  libreadline-dev libssl-dev unzip git pkg-config \
  libncurses5-dev libncursesw5-dev
# LuaJIT (optional) via apt
if [[ $WITH_LUAJIT -eq 1 ]]; then
  apt-get install -y --no-install-recommends luajit
fi
rm -rf /var/lib/apt/lists/*

# --- clean conflicting wrappers (if any) ---
for b in lua luac luarocks luajit; do
  rm -f "/usr/local/bin/$b" || true
done

# --- fresh target dir ---
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

# --- build & install Lua ---
echo "📦 Building Lua ${LUA_VERSION} ..."
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL "$LUA_TGZ" -o "$tmpdir/lua.tgz"
tar -xzf "$tmpdir/lua.tgz" -C "$tmpdir"
LUA_SRC_DIR="$(find "$tmpdir" -maxdepth 1 -type d -name "lua-*")"

# Lua's Makefile supports targets like "linux"
make -C "$LUA_SRC_DIR" linux MYCFLAGS="-DLUA_USE_READLINE" >/dev/null
make -C "$LUA_SRC_DIR" INSTALL_TOP="$TARGET_DIR" install >/dev/null

# --- build & install LuaRocks (bound to our Lua) ---
echo "📦 Installing LuaRocks ${LUAROCKS_VERSION} ..."
curl -fsSL "$LUAROCKS_TGZ" -o "$tmpdir/luarocks.tgz"
tar -xzf "$tmpdir/luarocks.tgz" -C "$tmpdir"
LR_SRC_DIR="$(find "$tmpdir" -maxdepth 1 -type d -name "luarocks-*")"

(
  cd "$LR_SRC_DIR"
  ./configure \
    --prefix="$TARGET_DIR" \
    --with-lua="$TARGET_DIR" \
    --with-lua-include="$TARGET_DIR/include" \
    --with-lua-lib="$TARGET_DIR/lib" >/dev/null
  make >/dev/null
  make install >/dev/null
)

# --- stable link ---
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- env for login shells ---
cat >/etc/profile.d/99-lua--profile.sh <<'EOF'
# Lua defaults under /opt
export LUA_HOME=/opt/lua-stable
export PATH="$LUA_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-lua--profile.sh

# --- multi-call wrapper for non-login shells ---
install -d /usr/local/bin
cat >/usr/local/bin/luawrap <<'EOF'
#!/bin/sh
: "${LUA_HOME:=/opt/lua-stable}"
export PATH="$LUA_HOME/bin:$PATH"
tool="$(basename "$0")"
# Prefer /opt Lua; fall back to system if not present (e.g., luajit from apt)
if [ -x "$LUA_HOME/bin/$tool" ]; then
  exec "$LUA_HOME/bin/$tool" "$@"
else
  exec "$(command -v "$tool")" "$@"
fi
EOF
chmod +x /usr/local/bin/luawrap

for t in lua luac luarocks; do
  ln -sfn /usr/local/bin/luawrap "/usr/local/bin/$t"
done

# If LuaJIT installed, expose it via wrapper as well (system binary)
if [[ $WITH_LUAJIT -eq 1 ]]; then
  ln -sfn /usr/local/bin/luawrap "/usr/local/bin/luajit"
fi

# --- friendly summary ---
echo "✅ Lua '${LUA_VERSION}' installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   lua:      "; /usr/local/bin/lua -v 2>&1 || true
echo -n "   luarocks: "; /usr/local/bin/luarocks --version 2>/dev/null | head -n1 || true
if [[ $WITH_LUAJIT -eq 1 ]]; then
  echo -n "   luajit:   "; /usr/local/bin/luajit -v 2>&1 | head -n1 || true
fi

cat <<'EON'
ℹ️ Ready to use:
- lua -v
- luarocks --help
- luarocks install busted    # example: install a test framework
- If installed, luajit -v

Notes:
- LuaRocks installs modules under /opt/lua-stable (kept with this Lua).
- To switch versions later, re-run this script with a different --lua-version.
EON
