#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Homebrew packages for the 'coder' user.
# It will install Homebrew if it is not already installed (276MB).
# Usage: brew--install.sh <package> [package...]

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
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

# No Homebrew packages requested is a no-op, not an error: the *-pkg templates emit
# `install brew ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No Homebrew packages requested; nothing to install."
    exit 0
fi

if [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    echo "brew is not installed."
    /opt/codingbooth/setups/brew--install.sh
fi

sudo -u coder /home/linuxbrew/.linuxbrew/bin/brew install "$@"
chown -R root:linuxbrew /home/linuxbrew
chmod -R g+w /home/linuxbrew
