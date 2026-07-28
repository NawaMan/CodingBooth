#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<LUA_VERSION>] [--lua-version <ver>] [--with-luarocks] [--with-luajit|--no-luajit]

Examples:
  $0                                # Lua 5.4 + LuaRocks
  $0 5.3                            # Pin Lua 5.3
  $0 --lua-version 5.4              # Pin Lua 5.4
  $0 --with-luajit                  # Also install LuaJIT

Supported versions: 5.1, 5.2, 5.3, 5.4

Notes:
- Installs Lua via apt (lua<ver> packages)
- LuaRocks is installed by default (use --no-luarocks to skip)
- Exposes lua/luac/luarocks via /usr/local/bin symlinks
- Optional: installs LuaJIT via apt (binary at /usr/bin/luajit)
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults ---
LUA_DEFAULT_VERSION="5.4"
WITH_LUAJIT=0
WITH_LUAROCKS=1

# --- parse args ---
LUA_VERSION_INPUT="${1:-}"
if [[ "$LUA_VERSION_INPUT" =~ ^- ]]; then LUA_VERSION_INPUT=""; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lua-version) shift; LUA_VERSION_INPUT="${1:-}"; shift ;;
    --with-luajit)    WITH_LUAJIT=1;    shift ;;
    --no-luajit)      WITH_LUAJIT=0;    shift ;;
    --with-luarocks)  WITH_LUAROCKS=1;  shift ;;
    --no-luarocks)    WITH_LUAROCKS=0;  shift ;;
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

# Strip patch version if provided (e.g., 5.4.7 -> 5.4, but leave 5.4 as-is)
if [[ "$LUA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  LUA_VERSION="${LUA_VERSION%.*}"
fi
if [[ ! "$LUA_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid version: ${LUA_VERSION} (expected major.minor like 5.4)"
  usage
  exit 2
fi

# --- install via apt ---
export DEBIAN_FRONTEND=noninteractive
echo "📦 Installing Lua ${LUA_VERSION} via apt ..."
apt-get update
apt-get install -y --no-install-recommends \
  "lua${LUA_VERSION}" "liblua${LUA_VERSION}-dev"

if [[ $WITH_LUAROCKS -eq 1 ]]; then
  # build-essential is not optional here: most rocks worth installing (busted pulls
  # luasystem, for one) carry a C component, and with no compiler luarocks fails while
  # probing for system libraries — "Could not find library file for RT" rather than
  # anything mentioning a missing gcc.
  apt-get install -y --no-install-recommends luarocks build-essential
fi

if [[ $WITH_LUAJIT -eq 1 ]]; then
  apt-get install -y --no-install-recommends luajit
fi

rm -rf /var/lib/apt/lists/*

# --- symlinks so "lua" and "luac" resolve without version suffix ---
for b in lua luac; do
  if command -v "${b}${LUA_VERSION}" >/dev/null 2>&1; then
    ln -sf "$(command -v "${b}${LUA_VERSION}")" "/usr/local/bin/${b}"
  fi
done

# --- env for login shells ---
cat >/etc/profile.d/99-lua--profile.sh <<EOF
# Lua ${LUA_VERSION} defaults
export LUA_VERSION=${LUA_VERSION}
EOF
chmod 0644 /etc/profile.d/99-lua--profile.sh

# --- friendly summary ---
echo ""
echo "✅ Lua ${LUA_VERSION} installed."
echo -n "   lua:      "; /usr/local/bin/lua -v 2>&1 || true
if [[ $WITH_LUAROCKS -eq 1 ]]; then
  echo -n "   luarocks: "; luarocks --version 2>/dev/null | head -n1 || true
fi
if [[ $WITH_LUAJIT -eq 1 ]]; then
  echo -n "   luajit:   "; luajit -v 2>&1 | head -n1 || true
fi

cat <<'EON'
ℹ️ Ready to use:
- lua -v
- luarocks --help
- luarocks install busted    # example: install a test framework

Notes:
- To switch versions, re-run with a different --lua-version.
EON
