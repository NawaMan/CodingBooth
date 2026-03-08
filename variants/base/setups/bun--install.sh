#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs global Bun packages for the 'coder' user.
# It requires bun--setup.sh to have been run first.
# Usage: bun--install.sh <package> [package...]

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

if ! command -v bun &> /dev/null; then
    echo "❌ Bun is not installed. Run bun--setup.sh first." >&2
    exit 1
fi

# Install global packages as coder user to avoid permission issues
sudo -u coder bun add -g "$@"
