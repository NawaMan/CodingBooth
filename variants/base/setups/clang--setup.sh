#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [<LLVM_VER>] [--version <LLVM_VER>] [--no-export-cc] [--no-as-default]

Examples:
  $0                   # installs LLVM/clang 18, exports CC/CXX, sets cc/c++ via alternatives
  $0 19                # installs LLVM/clang 19 (same defaults)
  $0 --version 17      # installs LLVM/clang 17
  $0 19 --no-export-cc # do NOT export CC/CXX for login shells
  $0 19 --no-as-default# do NOT set cc/c++ system-wide via update-alternatives

Defaults (can be disabled with the flags above):
- Exports: CC=clang, CXX=clang++ for login shells
- Registers: /usr/bin/cc and /usr/bin/c++ -> clang/clang++ via update-alternatives

Safe install set:
- Installs: clang/clang++, clangd, clang-tidy, clang-format, lld, libc++/libc++abi, libomp
- Does NOT switch the system linker to lld automatically
- Does NOT make libc++ the default C++ stdlib (use -stdlib=libc++)
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# --- defaults & args ---
LLVM_DEFAULT=18
LLVM_VER_INPUT="${1:-}"
[[ "$LLVM_VER_INPUT" =~ ^- ]] && LLVM_VER_INPUT=""
# Enabled by default; opt-out flags available
EXPORT_CC=1
AS_DEFAULT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)        shift; LLVM_VER_INPUT="${1:-}"; shift ;;
    --no-export-cc)   EXPORT_CC=0; shift ;;
    --no-as-default)  AS_DEFAULT=0; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)
      if [[ -z "$LLVM_VER_INPUT" ]]; then LLVM_VER_INPUT="$1"; shift
      else echo "❌ Unknown arg: $1"; usage; exit 2; fi
      ;;
  esac
done

LLVM_VER="${LLVM_VER_INPUT:-$LLVM_DEFAULT}"

LEVEL=63                          # See README.md - Profile Ordering

PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-clang--profile.sh"
PROFILE_CC_FILE="/etc/profile.d/${LEVEL}-cb-clang-cc--profile.sh"

# --- distro/codename (Ubuntu/Debian family) ---
if [ -r /etc/os-release ]; then . /etc/os-release; fi
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[[ -n "$CODENAME" ]] || { echo "❌ Could not determine Ubuntu/Debian codename"; exit 1; }

# --- base deps & repo key ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release software-properties-common

# --- pick a package source for LLVM ${LLVM_VER} ---
# Prefer Ubuntu's own repo when it ships the requested major (e.g. noble has
# clang-18 at 1:18.1.3 in universe). Falling through to apt.llvm.org is risky
# because all of its `llvm-toolchain-${CODENAME}{,-${LLVM_VER}}` repos currently
# ship snapshot builds (1:18.1.8~++20260421...) whose libllvm${LLVM_VER} declares
# `Breaks: llvm-${LLVM_VER}-dev (< 1:18.1.8-8)` — no llvm-${LLVM_VER}-dev at that
# threshold actually exists anywhere, so any install that hits the snapshot fails.
# Capture into a variable first — piping straight into `grep -q` makes grep
# close stdin early, which under `set -o pipefail` (the Dockerfile's SHELL
# default) propagates a SIGPIPE failure from `apt-cache madison` and breaks
# the conditional.
_CLANG_MADISON=$(apt-cache madison "clang-${LLVM_VER}" 2>/dev/null || true)
if [[ "$_CLANG_MADISON" == *"ubuntu-ports"* || "$_CLANG_MADISON" == *"archive.ubuntu.com"* ]]; then
  echo "📦 Using Ubuntu repo for LLVM ${LLVM_VER} (already available in ${CODENAME})"
else
  install -d /usr/share/keyrings
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key -o /usr/share/keyrings/llvm.asc
  cat >/etc/apt/sources.list.d/llvm-toolchain.list <<EOF
deb [signed-by=/usr/share/keyrings/llvm.asc] http://apt.llvm.org/${CODENAME}/ llvm-toolchain-${CODENAME}-${LLVM_VER} main
EOF
  apt-get update
fi

# --- package set (full but safe) ---
PKGS=(
  "clang-${LLVM_VER}"
  "llvm-${LLVM_VER}" "llvm-${LLVM_VER}-dev" "libclang-${LLVM_VER}-dev"
  "clang-tools-${LLVM_VER}" "clang-tidy-${LLVM_VER}" "clang-format-${LLVM_VER}" "clangd-${LLVM_VER}"
  "lld-${LLVM_VER}"
  "libc++-${LLVM_VER}-dev" "libc++abi-${LLVM_VER}-dev"
  "libomp-${LLVM_VER}-dev"
)
apt-get install -y --no-install-recommends "${PKGS[@]}"
rm -rf /var/lib/apt/lists/*

# --- paths & links ---
LLVM_PREFIX="/usr/lib/llvm-${LLVM_VER}"   # canonical prefix from the packages
[[ -d "$LLVM_PREFIX" ]] || { echo "❌ Expected LLVM prefix not found: $LLVM_PREFIX"; exit 1; }

INSTALL_PARENT=/opt/clang
TARGET_DIR="${INSTALL_PARENT}/clang-${LLVM_VER}"
LINK_DIR=/opt/clang-stable

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
ln -sfn "$LLVM_PREFIX" "${TARGET_DIR}/llvm-prefix"
ln -sfn "${TARGET_DIR}/llvm-prefix" "$LINK_DIR"

# --- login-shell env (PATH) ---
cat >"${PROFILE_FILE}" <<'EOF'
# Profile: LLVM/clang under /opt
export CLANG_HOME=/opt/clang-stable
case ":$PATH:" in
  *":$CLANG_HOME/bin:"*) ;;
  *) export PATH="$CLANG_HOME/bin:$PATH";;
esac
EOF
chmod 0644 "${PROFILE_FILE}"

# --- export CC/CXX by default (opt-out with --no-export-cc) ---
if [[ $EXPORT_CC -eq 1 ]]; then
  cat >"${PROFILE_CC_FILE}" <<'EOF'
# Profile: clang as default C/C++ compiler
export CC=clang
export CXX=clang++
EOF
  chmod 0644 "${PROFILE_CC_FILE}"
fi

# --- system-wide cc/c++ via update-alternatives (default; opt-out with --no-as-default) ---
if [[ $AS_DEFAULT -eq 1 ]]; then
  # Register the *versioned* clang binaries so multiple versions can coexist
  update-alternatives --install /usr/bin/cc  cc  "${LLVM_PREFIX}/bin/clang"    100
  update-alternatives --install /usr/bin/c++ c++ "${LLVM_PREFIX}/bin/clang++"  100
  # Make them the active alternatives now
  update-alternatives --set cc  "${LLVM_PREFIX}/bin/clang"
  update-alternatives --set c++ "${LLVM_PREFIX}/bin/clang++"
fi

# --- multi-call wrapper for non-login shells (/usr/local/bin) ---
install -d /usr/local/bin
cat >/usr/local/bin/clangwrap <<'EOF'
#!/bin/sh
: "${CLANG_HOME:=/opt/clang-stable}"
export PATH="$CLANG_HOME/bin:$PATH"
tool="$(basename "$0")"
if [ -x "$CLANG_HOME/bin/$tool" ]; then
  exec "$CLANG_HOME/bin/$tool" "$@"
fi
exec "$(command -v "$tool")" "$@"
EOF
chmod +x /usr/local/bin/clangwrap

# Symlink commonly-used tools to the wrapper
TOOLS="clang clang++ clang-cpp clangd clang-format clang-tidy lld ld.lld \
       llvm-ar llvm-ranlib llvm-objdump llvm-objcopy llvm-nm llvm-strings \
       llvm-addr2line llvm-size llvm-readelf llvm-readobj llvm-strip"
for t in $TOOLS; do
  ln -sfn /usr/local/bin/clangwrap "/usr/local/bin/$t"
done

# --- friendly summary ---
echo "✅ LLVM/clang ${LLVM_VER} installed."
echo "   PREFIX: $LLVM_PREFIX"
echo "   CLANG_HOME -> $LINK_DIR (-> $LLVM_PREFIX)"
echo -n "   clang:       "; /usr/local/bin/clang --version | head -n1 || true
echo -n "   clang++:     "; /usr/local/bin/clang++ --version | head -n1 || true
if command -v /usr/local/bin/clang-tidy >/dev/null 2>&1; then
  echo -n "   clang-tidy:  "; /usr/local/bin/clang-tidy --version | head -n1 || true
fi
if command -v /usr/local/bin/ld.lld >/dev/null 2>&1; then
  echo -n "   ld.lld:      "; /usr/local/bin/ld.lld --version | head -n1 || true
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: clang --version && clang++ --version
- Works in login & non-login shells (wrapper primes PATH).
- Defaults applied: CC/CXX exported; cc/c++ set via update-alternatives.

Notes:
- Safe defaults: GNU ld remains default; libstdc++ remains default (use -stdlib=libc++).
- With CMake:     -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
- Use lld:        clang++ -fuse-ld=lld ...
- Use libc++:     clang++ -stdlib=libc++ ...
- OpenMP:         clang++ -fopenmp your.cpp
EON
