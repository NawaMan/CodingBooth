#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Elixir Hex packages/archives globally via Mix.
# It requires elixir--setup.sh to have been run first.
# Usage: hex--install.sh <package[@version]> [package[@version]...]
# Example: hex--install.sh phx_new
#          hex--install.sh phx_new@1.7.0

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <package> [package...]"
        echo "Example: $0 phx_new"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No Hex packages requested is a no-op, not an error: the *-pkg templates emit
# `install hex ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No Hex packages requested; nothing to install."
    exit 0
fi

ELIXIR_HOME="${ELIXIR_HOME:-/opt/elixir-stable}"
MIX_HOME="${MIX_HOME:-/opt/mix}"
HEX_HOME="${HEX_HOME:-/opt/hex}"
export PATH="$ELIXIR_HOME/bin:$PATH"
export MIX_HOME HEX_HOME

if ! command -v mix &> /dev/null; then
    echo "Mix not found. Run elixir--setup.sh first." >&2
    exit 1
fi

# A trailing @version pins the archive (passed as mix's positional version arg).
for spec in "$@"; do
    pkg="${spec%@*}"
    if [ "$pkg" = "$spec" ]; then
        echo "Installing Hex package: $pkg"
        HOME="$MIX_HOME" mix archive.install hex "$pkg" --force
    else
        version="${spec##*@}"
        echo "Installing Hex package: $pkg (version $version)"
        HOME="$MIX_HOME" mix archive.install hex "$pkg" "$version" --force
    fi
done

echo "Hex packages installed to $MIX_HOME."
