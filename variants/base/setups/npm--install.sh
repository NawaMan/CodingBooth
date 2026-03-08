#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs global npm packages.
# It requires nodejs--setup.sh to have been run first.
# Usage: npm--install.sh <package> [package...]
#
# Note: Unlike pip/brew, npm global packages install to /usr/local/lib/node_modules
# which is root-owned. This script runs as root during Docker build.

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

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Run nodejs--setup.sh first." >&2
    exit 1
fi

# Install global packages as root (standard location: /usr/local/lib/node_modules)
npm install -g "$@"
