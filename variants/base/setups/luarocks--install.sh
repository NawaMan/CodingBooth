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

if [ $# -eq 0 ]; then
    echo "Usage: $0 <rock> [rock...]" >&2
    exit 1
fi

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

LUA_HOME="${LUA_HOME:-/opt/lua-stable}"
LUAROCKS="${LUA_HOME}/bin/luarocks"

if [ ! -x "$LUAROCKS" ]; then
    echo "LuaRocks not found at $LUAROCKS. Run lua--setup.sh first." >&2
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
