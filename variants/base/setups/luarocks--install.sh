#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs LuaRocks packages.
# It requires lua--setup.sh to have been run first.
# Usage: luarocks--install.sh <rock[@version]> [rock[@version]...]
# Example: luarocks--install.sh busted luasocket
#          luarocks--install.sh busted@2.0.0

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <rock> [rock...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No rocks requested is a no-op, not an error: the *-pkg templates emit
# `install luarocks ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No rocks requested; nothing to install."
    exit 0
fi

# lua--setup.sh installs LuaRocks from apt (/usr/bin/luarocks) and exposes it on
# PATH — there is no /opt/lua-stable tree. Honour an explicit LUA_HOME when it
# really holds a luarocks, otherwise just resolve it from PATH.
if [ -n "${LUA_HOME:-}" ] && [ -x "${LUA_HOME}/bin/luarocks" ]; then
    LUAROCKS="${LUA_HOME}/bin/luarocks"
else
    LUAROCKS="$(command -v luarocks || true)"
fi

if [ -z "$LUAROCKS" ] || [ ! -x "$LUAROCKS" ]; then
    echo "LuaRocks not found on PATH${LUA_HOME:+ or in $LUA_HOME/bin}. Run lua--setup.sh first." >&2
    exit 1
fi

# A trailing @version pins the rock (passed as luarocks' positional version arg).
# Splitting per-rock avoids the ambiguity of a bare positional version when
# installing multiple rocks at once.
for spec in "$@"; do
    rock="${spec%@*}"
    if [ "$rock" = "$spec" ]; then
        echo "Installing LuaRocks package: $rock"
        "$LUAROCKS" install "$rock"
    else
        version="${spec##*@}"
        echo "Installing LuaRocks package: $rock (version $version)"
        "$LUAROCKS" install "$rock" "$version"
    fi
done
