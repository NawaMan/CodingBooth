#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Installs the Conan (C/C++ package manager) binary only.
# To preload packages into the cache, use: install conan <pkg>[ <pkg>...]
# (which calls conan--install.sh).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

# This script will always be installed by root.
HOME=/root

if command -v conan >/dev/null 2>&1; then
  echo "ℹ️  Conan already installed: $(conan --version 2>&1 | head -n1)"
  exit 0
fi

echo "📦 Installing Conan ..."
if [ -x /opt/python/bin/pip ]; then
    /opt/python/bin/pip install conan
elif command -v pip3 >/dev/null 2>&1; then
    pip3 install conan
elif command -v pip >/dev/null 2>&1; then
    pip install conan
else
    echo "❌ No pip available to install conan. Install Python first." >&2
    exit 1
fi

echo -n "✅ Conan: "; conan --version 2>&1 | head -n1
