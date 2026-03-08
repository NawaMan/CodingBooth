#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Ruby gems for the 'coder' user.
# It requires ruby--setup.sh to have been run first.
# Usage: gem--install.sh <gem> [gem...]
# Example: gem--install.sh rails bundler pry

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <gem> [gem...]" >&2
    exit 1
fi

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

if [ ! -x /opt/rbenv/shims/gem ]; then
    echo "❌ Ruby is not installed. Run ruby--setup.sh first." >&2
    exit 1
fi

# Install gems as coder user so they go to coder's ~/.gem
for gem_name in "$@"; do
    echo "💎 Installing $gem_name..."
    sudo -u coder bash -lc "gem install '$gem_name' --no-document"
done
