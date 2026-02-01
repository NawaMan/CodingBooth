#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Haskell packages via Cabal.
# It requires haskell--setup.sh to have been run first.
# Usage: cabal--install.sh <package> [package...]
# Example: cabal--install.sh hlint pandoc

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <package> [package...]" >&2
    exit 1
fi

HASKELL_HOME="${HASKELL_HOME:-/opt/haskell-stable}"
export PATH="$HASKELL_HOME/.ghcup/bin:$HASKELL_HOME/.cabal/bin:$PATH"

if ! command -v cabal &> /dev/null; then
    echo "Cabal not found. Run haskell--setup.sh first." >&2
    exit 1
fi

echo "Updating cabal package index..."
cabal update

echo "Installing Haskell packages: $*"
cabal install --installdir=/usr/local/bin "$@"
