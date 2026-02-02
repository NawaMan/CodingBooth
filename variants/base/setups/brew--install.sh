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

if [ $# -eq 0 ]; then
    echo "Usage: $0 <package> [package...]" >&2
    exit 1
fi

if [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    echo "brew is not installed."
    /opt/codingbooth/setups/brew--install.sh
fi

sudo -u coder /home/linuxbrew/.linuxbrew/bin/brew install "$@"
chown -R root:linuxbrew /home/linuxbrew
chmod -R g+w /home/linuxbrew
