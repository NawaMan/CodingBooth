#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Python packages using uv into the shared Python venv.
# It requires python--setup.sh to have been run first.
# Usage: uv--install.sh <package> [package...]
# Example: uv--install.sh django flask numpy

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

# No uv packages requested is a no-op, not an error: the *-pkg templates emit
# `install uv ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No uv packages requested; nothing to install."
    exit 0
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "❌ uv is not installed. Run python--setup.sh first." >&2
    exit 1
fi

if [ ! -x /opt/python/bin/python ]; then
    echo "❌ Python is not set up. Run python--setup.sh first." >&2
    exit 1
fi

uv pip install --python /opt/python/bin/python "$@"
