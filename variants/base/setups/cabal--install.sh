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

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <package> [package...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No Cabal packages requested is a no-op, not an error: the *-pkg templates emit
# `install cabal ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No Cabal packages requested; nothing to install."
    exit 0
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
# --install-method=copy puts the real executable in /usr/local/bin. The default
# (symlink) points into root's cabal store under /root, which mode-0700 /root makes
# unreadable for the coder user the booth actually runs as — the binary then looks
# like a dangling symlink at runtime.
cabal install --installdir=/usr/local/bin --install-method=copy --overwrite-policy=always "$@"
