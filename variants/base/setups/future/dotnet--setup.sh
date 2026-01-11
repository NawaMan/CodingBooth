#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--channel 8.0|9.0|LTS|current] [--sdk-version <x.y.z>] [--runtime aspnet|dotnet]
     [--with-wasm-tools] [--nuget-dir </path>]

Examples:
  $0                               # SDK channel 8.0 (LTS) → /opt/dotnet/dotnet-8.0
  $0 --channel 9.0                 # SDK channel 9.0 (current)
  $0 --sdk-version 9.0.100         # pin exact SDK version
  $0 --runtime aspnet              # runtime-only (no SDK), ASP.NET Core runtime
  $0 --with-wasm-tools             # install workloads: wasm-tools (requires SDK)
  $0 --nuget-dir /opt/nuget        # custom NuGet cache dir

Notes:
- Uses official dotnet-install.sh (no apt packages), installs under /opt/dotnet
- Stable link /opt/dotnet-stable + /usr/local/bin/dotnet wrapper for non-login shells
- NuGet cache defaults to /opt/nuget-packages (world-writable)
- Works on amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
CHANNEL_DEFAULT="8.0"      # safe default: LTS channel
CHANNEL="$CHANNEL_DEFAULT"
SDK_VERSION=""             # exact version; if set, overrides channel for SDK installs
RUNTIME_KIND=""            # empty → install SDK; or: aspnet | dotnet
WITH_WASM_TOOLS=0
NUGET_DIR_DEFAULT="/opt/nuget-packages"
NUGET_DIR="$NUGET_DIR_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) shift; CHANNEL="${1:-$CHANNEL_DEFAULT}"; shift ;;
    --sdk-version) shift; SDK_VERSION="${1:-}"; shift ;;
    --runtime) shift; RUNTIME_KIND="${1:-}"; shift ;;
    --with-wasm-tools) WITH_WASM_TOOLS=1; shift ;;
    --nuget-dir) shift; NUGET_DIR="${1:-$NUGET_DIR_DEFAULT}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch guard ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# ---- base tools ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip
rm -rf /var/lib/apt/lists/*

# ---- dirs ----
INSTALL_PARENT=/opt/dotnet
if [[ -n "$RUNTIME_KIND" ]]; then
  TARGET_DIR="${INSTALL_PARENT}/dotnet-${RUNTIME_KIND}-${CHANNEL:-runtime}"
else
  # SDK layout keyed by channel unless exact version specified
  TARGET_DIR="${INSTALL_PARENT}/dotnet-${SDK_VERSION:-$CHANNEL}"
fi
LINK_DIR=/opt/dotnet-stable
BIN_DIR=/usr/local/bin

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR" "$INSTALL_PARENT" "$NUGET_DIR"
chmod -R 0777 "$NUGET_DIR" || true

# ---- fetch official installer ----
DOTNET_INSTALL=/tmp/dotnet-install.sh
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$DOTNET_INSTALL"
chmod +x "$DOTNET_INSTALL"

# ---- install SDK or runtime ----
if [[ -z "$RUNTIME_KIND" ]]; then
  # SDK install
  if [[ -n "$SDK_VERSION" ]]; then
    echo "📦 Installing .NET SDK ${SDK_VERSION} → ${TARGET_DIR}"
    "$DOTNET_INSTALL" --install-dir "$TARGET_DIR" --version "$SDK_VERSION"
  else
    echo "📦 Installing .NET SDK channel ${CHANNEL} → ${TARGET_DIR}"
    "$DOTNET_INSTALL" --install-dir "$TARGET_DIR" --channel "$CHANNEL"
  fi
else
  # Runtime-only install
  case "$RUNTIME_KIND" in
    aspnet|dotnet) ;;
    *) echo "❌ --runtime must be 'aspnet' or 'dotnet'"; exit 2 ;;
  esac
  echo "📦 Installing .NET runtime (${RUNTIME_KIND}) channel ${CHANNEL} → ${TARGET_DIR}"
  "$DOTNET_INSTALL" --install-dir "$TARGET_DIR" --channel "$CHANNEL" --runtime "$RUNTIME_KIND"
fi

# ---- stable link ----
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login-shell env ----
cat >/etc/profile.d/99-dotnet--profile.sh <<EOF
# .NET under /opt
export DOTNET_ROOT=$LINK_DIR
export PATH="\$DOTNET_ROOT:\$PATH"
# Shared NuGet cache (CI/dev friendly)
export NUGET_PACKAGES=${NUGET_DIR}
EOF
chmod 0644 /etc/profile.d/99-dotnet--profile.sh

# ---- non-login wrapper ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/dotnet" <<'EOF'
#!/bin/sh
: "${DOTNET_ROOT:=/opt/dotnet-stable}"
: "${NUGET_PACKAGES:=/opt/nuget-packages}"
export DOTNET_ROOT NUGET_PACKAGES PATH="$DOTNET_ROOT:$PATH"
exec "$DOTNET_ROOT/dotnet" "$@"
EOF
chmod +x "${BIN_DIR}/dotnet"

# ---- optional workloads (SDK only) ----
if [[ -z "$RUNTIME_KIND" && $WITH_WASM_TOOLS -eq 1 ]]; then
  echo "🔧 Installing workloads: wasm-tools"
  DOTNET_ROOT="$LINK_DIR" NUGET_PACKAGES="$NUGET_DIR" "$BIN_DIR/dotnet" workload install wasm-tools --skip-manifest-update || true
fi

# ---- friendly summary ----
echo "✅ .NET installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo "   NUGET_PACKAGES = ${NUGET_DIR}"
echo -n "   dotnet --info → "; "${BIN_DIR}/dotnet" --info | sed -n '1,8p' || true

cat <<'EON'
ℹ️ Ready to use:
- Try: dotnet --info
- Works in login & non-login shells (wrapper primes PATH, DOTNET_ROOT, NuGet cache).
- Pin SDK per project with a global.json, e.g.:
    {
      "sdk": { "version": "8.0.400", "rollForward": "latestFeature" }
    }

Tips:
- Install another channel/version by re-running this script (updates /opt/dotnet-stable).
- Runtime-only mode is for production images; SDK mode is for development/CI.
- Cache speedups in CI: persist /opt/nuget-packages between runs.
EON
