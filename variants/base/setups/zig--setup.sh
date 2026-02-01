#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<ZIG_VERSION>] [--zig-version <ZIG_VERSION>] [--no-verify] [--no-alternatives]

Examples:
  $0                          # install default (latest stable) and register as lowest-priority cc/c++
  $0 0.14.1                   # pin a version
  $0 --zig-version 0.15.1     # equivalent
  $0 0.15.1 --no-verify       # skip minisign verification
  $0 --no-alternatives        # do NOT register cc/c++ (just install zig)
USAGE
}

# --- root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# --- defaults ---
ZIG_DEFAULT_VERSION="${ZIG_DEFAULT_VERSION:-0.15.1}"   # latest stable on 2025-09-26
ZIG_VERSION_INPUT="${1:-}"
if [[ "${ZIG_VERSION_INPUT}" =~ ^- ]] ; then ZIG_VERSION_INPUT=""; fi

NO_VERIFY=0
USE_ALTS=1   # register with update-alternatives by default (lowest priority)
# parse flags (+ optional positional version)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zig-version) shift; ZIG_VERSION_INPUT="${1:-}"; shift ;;
    --no-verify)   NO_VERIFY=1; shift ;;
    --no-alternatives) USE_ALTS=0; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)
      if [[ -z "${ZIG_VERSION_INPUT}" ]]; then ZIG_VERSION_INPUT="$1"; shift
      else echo "❌ Unknown argument: $1"; usage; exit 2; fi
      ;;
  esac
done
ZIG_VERSION="${ZIG_VERSION_INPUT:-$ZIG_DEFAULT_VERSION}"

# --- arch mapping ---
dpkg_arch="$(dpkg --print-architecture)"
case "$dpkg_arch" in
  amd64) ZIG_ARCH="x86_64" ;;
  arm64) ZIG_ARCH="aarch64" ;;
  *) echo "❌ Unsupported architecture: $dpkg_arch (supported: amd64, arm64)" >&2; exit 2 ;;
esac

INSTALL_PARENT=/opt/zig
TARGET_DIR="${INSTALL_PARENT}/zig-${ZIG_VERSION}"
LINK_DIR=/opt/zig-stable
BASE_URL="https://ziglang.org/download/${ZIG_VERSION}"

# --- base tools ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates xz-utils tar coreutils minisign
rm -rf /var/lib/apt/lists/*

# --- try both historical filename patterns ---
fname_new="zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz"   # e.g. 0.15.1
fname_old="zig-linux-${ZIG_ARCH}-${ZIG_VERSION}.tar.xz"   # e.g. 0.14.0
TMP="/tmp"
download_one() {
  local name="$1"
  echo "Attempting download: ${BASE_URL}/${name}"
  curl -fsSL "${BASE_URL}/${name}" -o "${TMP}/${name}"
}

if ! download_one "$fname_new"; then
  echo "Fallback to legacy filename pattern..."
  if ! download_one "$fname_old"; then
    echo "❌ Could not download Zig ${ZIG_VERSION} for ${ZIG_ARCH} from ${BASE_URL}" >&2
    exit 3
  else
    FILENAME="$fname_old"
  fi
else
  FILENAME="$fname_new"
fi

# --- verify with minisign (optional) ---
# Zig's minisign public key (from the downloads page)
PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"
if [ "$NO_VERIFY" -eq 0 ]; then
  echo "Verifying minisign signature..."
  if curl -fsSL "${BASE_URL}/${FILENAME}.minisig" -o "${TMP}/${FILENAME}.minisig"; then
    minisign -Vm "${TMP}/${FILENAME}" -P "$PUBKEY" -x "${TMP}/${FILENAME}.minisig"
  else
    echo "⚠️  Signature file not found; proceeding without verification."
  fi
else
  echo "⚠️  Verification disabled by --no-verify."
fi

# --- install into versioned dir ---
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
tar -xJf "${TMP}/${FILENAME}" -C "$TARGET_DIR" --strip-components=1
rm -f "${TMP}/${FILENAME}" "${TMP}/${FILENAME}.minisig" || true

# --- stable symlink ---
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- expose zig for non-login shells ---
install -d /usr/local/bin
ln -sfn "$LINK_DIR/zig" /usr/local/bin/zig

# --- login-shell env (opt-in to use zig as cc/c++) ---
cat >/etc/profile.d/99-zig--profile.sh <<'EOF'
# Zig defaults
export ZIG_HOME=/opt/zig-stable
export PATH="$ZIG_HOME:$PATH"
# Opt-in: use Zig as the C/C++ compiler for this shell
#   export ZIG_AS_CC=1
if [ "${ZIG_AS_CC:-0}" = "1" ]; then
  export CC="zig cc"
  export CXX="zig c++"
fi
EOF
chmod 0644 /etc/profile.d/99-zig--profile.sh

# --- tiny shims so update-alternatives can point cc/c++ at zig ---
cat >/usr/local/bin/zig-cc <<'EOF'
#!/bin/sh
exec zig cc "$@"
EOF
cat >/usr/local/bin/zig-c++ <<'EOF'
#!/bin/sh
exec zig c++ "$@"
EOF
chmod +x /usr/local/bin/zig-cc /usr/local/bin/zig-c++

# --- register as the lowest-priority alternative (optional) ---
if [ "$USE_ALTS" -eq 1 ]; then
  # Priority 25 (lower than clang=100/200, gcc=50)
  update-alternatives --install /usr/bin/cc  cc  /usr/local/bin/zig-cc   25
  update-alternatives --install /usr/bin/c++ c++ /usr/local/bin/zig-c++  25
fi

echo "✅ Zig ${ZIG_VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   zig: "; /usr/local/bin/zig version || true
if [ "$USE_ALTS" -eq 1 ]; then
  echo "   Registered with update-alternatives (priority 25) for cc/c++."
  echo "   Current cc  -> $(command -v cc || true)"
  echo "   Current c++ -> $(command -v c++ || true)"
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: zig version
- To use Zig as your compiler in this shell only:
    export ZIG_AS_CC=1
- To switch system-wide compiler:
    sudo update-alternatives --config cc
    sudo update-alternatives --config c++
EON
