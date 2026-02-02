#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Conda packages for the 'coder' user.
# It requires conda--setup.sh to have been run first.
# Usage: conda--install.sh <package> [package...]
# Example: conda--install.sh numpy pandas matplotlib

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

CONDA_ROOT="/opt/conda"
CONDA_ENV="/opt/python"

if [ ! -x "$CONDA_ROOT/bin/conda" ]; then
    echo "❌ Conda is not installed. Run conda--setup.sh first." >&2
    exit 1
fi

# Install packages into the default environment
echo "📦 Installing conda packages: $*"
if [ -d "$CONDA_ENV" ]; then
    "$CONDA_ROOT/bin/conda" install -y -p "$CONDA_ENV" "$@"
else
    "$CONDA_ROOT/bin/conda" install -y "$@"
fi
