#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Conan (C/C++ package manager) and optionally packages.
# Usage: conan--install.sh [package[@version] ...]
# Example: conan--install.sh
#          conan--install.sh boost/1.83.0 fmt/10.1.1

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

# Install conan via pip if not present
if ! command -v conan &> /dev/null; then
    echo "📦 Installing Conan..."
    if [ -x /opt/python/bin/pip ]; then
        /opt/python/bin/pip install conan
    else
        pip3 install conan
    fi
fi

# Verify installation
conan --version

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# If packages are specified, download them to cache
if [ $# -gt 0 ]; then
    # Download as coder, not root: the Conan cache lives in $HOME/.conan2, and a
    # root-owned /root/.conan2 is invisible to the coder user the booth runs as —
    # the packages would be "installed" into a cache nobody ever reads.
    CONAN_BIN="$(command -v conan)"
    echo "📦 Downloading Conan packages to cache..."
    for pkg in "$@"; do
        echo "  Downloading $pkg..."
        # No `|| true` — a package that fails to download must fail the build rather
        # than leave an empty cache behind a green image.
        sudo -u coder -H "$CONAN_BIN" download "$pkg" -r conancenter
    done
fi

echo "✅ Conan is ready"
