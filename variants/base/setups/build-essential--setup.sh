#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Installs Ubuntu's build-essential meta-package (gcc, g++, make, libc-dev,
# dpkg-dev) plus pkg-config. This is the minimal toolchain that lets pip / npm /
# cargo / etc. compile native extensions, and lets CMake's find_package +
# pkg-config resolve common system libraries (libssl-dev, zlib1g-dev, ...).
#
# This is intentionally distinct from `setup gcc` / `setup clang`, which install
# a *specific pinned version* into /opt with profile.d wiring and update-
# alternatives. Use this when you just need "a standard toolchain".

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

# This script will always be installed by root.
HOME=/root

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  pkg-config
rm -rf /var/lib/apt/lists/*

echo "✅ build-essential installed:"
echo -n "   gcc:        "; gcc --version 2>/dev/null | head -n1 || echo "(not found)"
echo -n "   g++:        "; g++ --version 2>/dev/null | head -n1 || echo "(not found)"
echo -n "   make:       "; make --version 2>/dev/null | head -n1 || echo "(not found)"
echo -n "   pkg-config: "; pkg-config --version 2>/dev/null || echo "(not found)"

cat <<'EON'
ℹ️ Notes:
- Provides the standard Ubuntu toolchain (gcc, g++, make, libc-dev, pkg-config).
- For a *pinned* compiler version, use 'setup gcc --version <N>' or 'setup clang --version <N>' instead.
- Both forms coexist: pinned compilers register at higher update-alternatives
  priority and stay the default cc/c++.
EON
