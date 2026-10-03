#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs .NET SDK at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root


# --- Defaults ---
CHANNEL="9.0"
SDK_VERSION=""
RUNTIME_KIND=""
WITH_WASM_TOOLS=0
NUGET_DIR="/opt/nuget-packages"

LEVEL=57

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-dotnet--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-dotnet--profile.sh"
STARTER_FILE="/usr/local/bin/dotnet"

# --- Parse args ---
# First positional arg is channel (for simple usage: setup dotnet 9.0)
if [[ $# -ge 1 && ! "$1" =~ ^-- ]]; then
  CHANNEL="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)       shift; CHANNEL="${1:-$CHANNEL}"; shift ;;
    --sdk-version)   shift; SDK_VERSION="${1:-}"; shift ;;
    --runtime)       shift; RUNTIME_KIND="${1:-}"; shift ;;
    --with-wasm-tools) WITH_WASM_TOOLS=1; shift ;;
    --nuget-dir)     shift; NUGET_DIR="${1:-$NUGET_DIR}"; shift ;;
    *) echo "❌ Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Arch guard ---
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|aarch64) ;;
  *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ==== Install .NET SDK ====

# Base tools (curl is needed for dotnet-install.sh)
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends curl ca-certificates libicu-dev
rm -rf /var/lib/apt/lists/*

# Directories
INSTALL_PARENT=/opt/dotnet
if [[ -n "$RUNTIME_KIND" ]]; then
  TARGET_DIR="${INSTALL_PARENT}/dotnet-${RUNTIME_KIND}-${CHANNEL:-runtime}"
else
  TARGET_DIR="${INSTALL_PARENT}/dotnet-${SDK_VERSION:-$CHANNEL}"
fi
LINK_DIR=/opt/dotnet-stable

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR" "$INSTALL_PARENT" "$NUGET_DIR"
chmod -R 0777 "$NUGET_DIR" || true

# Fetch official installer
DOTNET_INSTALL=/tmp/dotnet-install.sh
echo "📦 Downloading .NET installer..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL https://dot.net/v1/dotnet-install.sh -o "$DOTNET_INSTALL"
chmod +x "$DOTNET_INSTALL"

# Install SDK or runtime
if [[ -z "$RUNTIME_KIND" ]]; then
  if [[ -n "$SDK_VERSION" ]]; then
    echo "📦 Installing .NET SDK ${SDK_VERSION} → ${TARGET_DIR}"
    "$DOTNET_INSTALL" --install-dir "$TARGET_DIR" --version "$SDK_VERSION"
  else
    echo "📦 Installing .NET SDK channel ${CHANNEL} → ${TARGET_DIR}"
    "$DOTNET_INSTALL" --install-dir "$TARGET_DIR" --channel "$CHANNEL"
  fi
else
  case "$RUNTIME_KIND" in
    aspnet|dotnet) ;;
    *) echo "❌ --runtime must be 'aspnet' or 'dotnet'"; exit 2 ;;
  esac
  echo "📦 Installing .NET runtime (${RUNTIME_KIND}) channel ${CHANNEL} → ${TARGET_DIR}"
  "$DOTNET_INSTALL" --install-dir "$TARGET_DIR" --channel "$CHANNEL" --runtime "$RUNTIME_KIND"
fi

rm -f "$DOTNET_INSTALL"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# Optional workloads (SDK only)
if [[ -z "$RUNTIME_KIND" && $WITH_WASM_TOOLS -eq 1 ]]; then
  echo "🔧 Installing workloads: wasm-tools"
  DOTNET_ROOT="$LINK_DIR" NUGET_PACKAGES="$NUGET_DIR" \
    "$LINK_DIR/dotnet" workload install wasm-tools --skip-manifest-update || true
fi

# ---- Create startup file ----
export CHANNEL NUGET_DIR
envsubst '$CHANNEL $NUGET_DIR' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SENTINEL="$HOME/.dotnet-startup-done"
[[ -f "$SENTINEL" ]] || {
  # Ensure user-level tool path exists
  mkdir -p "$HOME/.dotnet/tools"
  touch "$SENTINEL"
}
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file ----
export LINK_DIR NUGET_DIR
envsubst '$LINK_DIR $NUGET_DIR' > "${PROFILE_FILE}" <<'EOF'
# Profile: .NET SDK

# DOTNET_ROOT points to the stable symlink
export DOTNET_ROOT=$LINK_DIR

# Add dotnet to PATH if not already there
case ":$PATH:" in
  *":$DOTNET_ROOT:"*) ;;
  *) export PATH="$DOTNET_ROOT:$PATH" ;;
esac

# User-installed dotnet tools
case ":$PATH:" in
  *":$HOME/.dotnet/tools:"*) ;;
  *) export PATH="$HOME/.dotnet/tools:$PATH" ;;
esac

# Shared NuGet cache
export NUGET_PACKAGES=$NUGET_DIR

# Disable telemetry in container environments
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# Skip first-run experience (faster startup)
export DOTNET_NOLOGO=1
EOF
chmod 644 "${PROFILE_FILE}"

# ---- Create starter file (non-login shell wrapper) ----
cat > "${STARTER_FILE}" <<'EOF'
#!/bin/sh
: "${DOTNET_ROOT:=/opt/dotnet-stable}"
: "${NUGET_PACKAGES:=/opt/nuget-packages}"
export DOTNET_ROOT NUGET_PACKAGES DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
export PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$PATH"
exec "$DOTNET_ROOT/dotnet" "$@"
EOF
chmod 755 "${STARTER_FILE}"

# ---- Summary ----
INSTALLED_VERSION=$("$LINK_DIR/dotnet" --version 2>/dev/null || echo "unknown")
echo "✅ .... .NET is installed ...."
echo "• Version: ${INSTALLED_VERSION} (channel ${CHANNEL})"
echo "• Startup file (container login) : ${STARTUP_FILE}"
echo "• Profile file (every user shell): ${PROFILE_FILE}"
echo "• Starter file (the executable)  : ${STARTER_FILE}"
echo "• Install directory              : ${TARGET_DIR}"
echo "• Stable symlink                 : ${LINK_DIR} -> ${TARGET_DIR}"
echo "• NuGet cache                    : ${NUGET_DIR}"
echo ""
echo "You may source the profile above to start using .NET in this session."
