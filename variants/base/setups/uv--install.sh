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

if [ $# -eq 0 ]; then
    echo "Usage: $0 <package> [package...]" >&2
    exit 1
fi

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

if ! command -v uv >/dev/null 2>&1; then
    echo "❌ uv is not installed. Run python--setup.sh first." >&2
    exit 1
fi

if [ ! -x /opt/python/bin/python ]; then
    echo "❌ Python is not set up. Run python--setup.sh first." >&2
    exit 1
fi

uv pip install --python /opt/python/bin/python "$@"
