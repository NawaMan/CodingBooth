#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

# This script installs Haskell packages via Cabal.
# It requires haskell--setup.sh to have been run first.
# Usage: cabal--install.sh <package> [package...]
# Example: cabal--install.sh hlint pandoc

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# cb_retry retries the network-bound install below past a transient registry
# error (a 5xx, a dropped connection) and nothing else, so a bad package name
# still fails on the first attempt. The lib sits beside this script both in the
# image (/opt/codingbooth/setups/) and in the repo, so a host-run test finds it.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

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

# hlint and ormolu come prebuilt from NawaMan/CodingBoothPrebuilt, at the version asked for
# (hlint, hlint-3.10 or hlint==3.10) or Hackage's newest preferred one. They land the way
# haskell-tools--setup.sh lays them out -- /opt/haskell-tools/<tool>-<version>, hlint's data/
# beside it, linked into /usr/local/bin -- so `hlint` finds its hints either way. Any cabal
# flag in the line asks for a specific build, so then everything is compiled, as is any
# other package or a version with no asset yet.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-packages.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-packages.sh"

TOOLS_ROOT="${CB_HASKELL_TOOLS_ROOT:-/opt/haskell-tools}"
PREBUILT_OK=true
for arg in "$@"; do
    case "$arg" in -*) PREBUILT_OK=false ;; esac
done
TO_BUILD=()
for spec in "$@"; do
    if [ "$PREBUILT_OK" = true ] && found="$(cb_prebuilt_cabal "$spec")"; then
        read -r tool version <<< "$found"
        dest="${TOOLS_ROOT}/${tool}-${version}"
        rm -rf "$dest"
        if cb_prebuilt_install "$tool" "$version" native "$dest"; then
            chmod -R a+rX "$dest"
            ln -sfn "$dest/$tool" "/usr/local/bin/$tool"
            echo "✅ $spec → prebuilt $tool $version, linked as /usr/local/bin/$tool"
            continue
        fi
        echo "ℹ️  $tool $version: not prebuilt for this image; building with cabal..."
    fi
    TO_BUILD+=("$spec")
done
if [ ${#TO_BUILD[@]} -eq 0 ]; then
    exit 0
fi
set -- "${TO_BUILD[@]}"

echo "Updating cabal package index..."
cb_retry cabal update

echo "Installing Haskell packages: $*"
# --install-method=copy puts the real executable in /usr/local/bin. The default
# (symlink) points into root's cabal store under /root, which mode-0700 /root makes
# unreadable for the coder user the booth actually runs as — the binary then looks
# like a dangling symlink at runtime.
cb_retry cabal install --installdir=/usr/local/bin --install-method=copy --overwrite-policy=always "$@"
