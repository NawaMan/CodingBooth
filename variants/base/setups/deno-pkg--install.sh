#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Deno packages for the 'coder' user.
# Packages are passed as a comma-separated list.
# It requires deno--setup.sh to have been run first.
# Usage: deno-pkg--install.sh <pkg1,pkg2,...>
# Examples:
#   deno-pkg--install.sh npm:cowsay
#   deno-pkg--install.sh npm:cowsay,npm:figlet

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "Usage: $0 <pkg1,pkg2,...>" >&2
    echo "Examples:" >&2
    echo "  $0 npm:cowsay" >&2
    echo "  $0 npm:cowsay,npm:figlet" >&2
    exit 1
fi

if ! command -v deno &> /dev/null; then
    echo "❌ Deno is not installed. Run deno--setup.sh first." >&2
    exit 1
fi

# Split comma-separated packages and install each
IFS=',' read -ra PKGS <<< "$1"
for pkg in "${PKGS[@]}"; do
    pkg=$(echo "$pkg" | xargs) # trim whitespace
    if [ -n "$pkg" ]; then
        echo "📦 Installing: deno add $pkg"
        sudo -u coder bash -lc "cd /home/coder && deno add $pkg"
    fi
done
