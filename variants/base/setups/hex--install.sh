#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Elixir Hex packages/archives globally via Mix.
# It requires elixir--setup.sh to have been run first.
# Usage: hex--install.sh <package> [package...]
# Example: hex--install.sh phx_new

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <package> [package...]" >&2
    echo "Example: $0 phx_new" >&2
    exit 1
fi

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

ELIXIR_HOME="${ELIXIR_HOME:-/opt/elixir-stable}"
MIX_HOME="${MIX_HOME:-/opt/mix}"
HEX_HOME="${HEX_HOME:-/opt/hex}"
export PATH="$ELIXIR_HOME/bin:$PATH"
export MIX_HOME HEX_HOME

if ! command -v mix &> /dev/null; then
    echo "Mix not found. Run elixir--setup.sh first." >&2
    exit 1
fi

for pkg in "$@"; do
    echo "Installing Hex package: $pkg"
    HOME="$MIX_HOME" mix archive.install hex "$pkg" --force
done

echo "Hex packages installed to $MIX_HOME."
