#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Go packages for the 'coder' user.
# It requires go--setup.sh to have been run first.
# Usage: go--install.sh <package@version> [package@version...]
# Example: go--install.sh golang.org/x/tools/gopls@latest

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <package@version> [package@version...]" >&2
    exit 1
fi

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

if [ ! -x /usr/local/go-current/bin/go ]; then
    echo "❌ Go is not installed. Run go--setup.sh first." >&2
    exit 1
fi

# Source go profile to set up GOPATH
source /etc/profile.d/*-cb-go--profile.sh 2>/dev/null || true

# Install packages as coder user so they go to coder's GOPATH
for pkg in "$@"; do
    sudo -u coder bash -lc "go install '$pkg'"
done
