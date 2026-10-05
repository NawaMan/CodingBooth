#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# --- Defaults ---
JULIA_VERSION="${1:-1.11.3}"

LEVEL=60

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-julia--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-julia--profile.sh"

# ---- validate version format ----
if [[ ! "$JULIA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Version must be X.Y.Z (e.g., 1.11.3)"; exit 2
fi

MAJOR="${JULIA_VERSION%%.*}"
REST="${JULIA_VERSION#*.}"
MINOR="${REST%%.*}"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) SHORT_ARCH="x64";     FULL_ARCH="x86_64"  ;;
  arm64) SHORT_ARCH="aarch64"; FULL_ARCH="aarch64"  ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar
rm -rf /var/lib/apt/lists/*

# ---- download and install ----
TAR_URL="https://julialang-s3.julialang.org/bin/linux/${SHORT_ARCH}/${MAJOR}.${MINOR}/julia-${JULIA_VERSION}-linux-${FULL_ARCH}.tar.gz"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Julia ${JULIA_VERSION} (${FULL_ARCH}) ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$TAR_URL" -o "$TMP/julia.tar.gz"

echo "📦 Extracting to /opt/julia-${JULIA_VERSION} ..."
rm -rf "/opt/julia-${JULIA_VERSION}"
mkdir -p "/opt/julia-${JULIA_VERSION}"
tar -xzf "$TMP/julia.tar.gz" -C "/opt/julia-${JULIA_VERSION}" --strip-components=1

echo "🔗 Creating symlink /opt/julia -> /opt/julia-${JULIA_VERSION} ..."
ln -sfn "/opt/julia-${JULIA_VERSION}" /opt/julia

# ---- Create profile file ----
export JULIA_VERSION
envsubst '$JULIA_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: Julia: $JULIA_VERSION

# ==== Things to do at shell login by user. ====
case ":$PATH:" in
  *":/opt/julia/bin:"*) ;;
  *) export PATH="/opt/julia/bin:$PATH";;
esac

export JULIA_DEPOT_PATH="$HOME/.julia"
EOF
chmod 644 "${PROFILE_FILE}"

# ---- Create startup file ----
envsubst '$JULIA_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Julia startup: create .julia directory
mkdir -p "$HOME/.julia"
EOF
chmod 755 "${STARTUP_FILE}"

# ---- friendly summary ----
echo "✅ .... Julia is installed ...."
echo "• Version: ${JULIA_VERSION}"
echo "• Install dir: /opt/julia-${JULIA_VERSION}"
echo "• Symlink:     /opt/julia -> /opt/julia-${JULIA_VERSION}"
echo "• Startup file (container login) : ${STARTUP_FILE}"
echo "• Profile file (every user shell): ${PROFILE_FILE}"
echo ""
echo "You may source the profile above to start using Julia in this session."
