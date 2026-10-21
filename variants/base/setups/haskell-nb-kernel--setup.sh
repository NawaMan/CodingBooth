#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.2.0

# haskell-nb-kernel--setup.sh
#
# Installs the IHaskell Jupyter kernel.
# IHaskell provides interactive Haskell in Jupyter notebooks.
#
# Usage: haskell-nb-kernel--setup.sh [--ihaskell-version <ver>] [--ghc-version <ver>|current]
#
# The kernel embeds the GHC API, so it is built for one exact GHC. That is GHC 9.12.4 by
# default, not the booth's own GHC: IHaskell 0.13 on GHC 9.10.3 (ghcup's "recommended")
# kills the kernel ("ARR_WORDS object entered") when the first cell to import Data.Map
# also calls insertWith/fromListWith. When the booth's GHC is another version, ghcup
# installs the kernel's GHC beside it without changing the default, so `ghc` in the
# terminal stays as it was; packages installed for that GHC are not visible in notebooks.
# `--ghc-version current` uses the booth's GHC instead.
#
# For that GHC, IHaskell comes prebuilt (sha256-checked) from
# https://github.com/NawaMan/CodingBoothPrebuilt/releases when a build is published for
# it; otherwise it is built from source with cabal (about 11 minutes on 4 cores).
# Either way it lands in /opt/ihaskell/ihaskell-<ver>-ghc<ghc>: the binary finds its data
# files (kernel.js, hlint.yaml) through paths fixed at build time, so the folder is the
# same for both and readable by every user.
#
# Prereqs:
#   - haskell--setup.sh already ran successfully (ghc, cabal on PATH).
#   - python--setup.sh and notebook--setup.sh already ran.
#   - /etc/profile.d/53-cb-python--profile.sh should be sourced.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

# ---------------- Load environment from profile.d ----------------
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
[ -f /etc/profile.d/99-haskell--profile.sh ] && source /etc/profile.d/99-haskell--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
IHASKELL_VERSION="0.13.0.0"
KERNEL_GHC_VERSION="9.12.4"
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-haskell}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Haskell (IHaskell)}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ihaskell-version) shift; IHASKELL_VERSION="${1:?--ihaskell-version needs a value}"; shift ;;
    --ghc-version)      shift; KERNEL_GHC_VERSION="${1:?--ghc-version needs a value}"; shift ;;
    -h|--help) echo "Usage: $0 [--ihaskell-version <ver>] [--ghc-version <ver>|current]"; exit 0 ;;
    *) echo "❌ Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v ghc >/dev/null 2>&1; then
  echo "❌ GHC is not installed or not on PATH." >&2
  exit 1
fi

if ! command -v cabal >/dev/null 2>&1; then
  echo "❌ Cabal is not installed or not on PATH." >&2
  exit 1
fi

# Ensure python has jupyter_client and jupyter_core
if ! python - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if all(u.find_spec(m) for m in ("jupyter_client","jupyter_core")) else 1)
PY
then
  echo "❌ python lacks required Jupyter packages ('jupyter_client' and/or 'jupyter_core')." >&2
  exit 2
fi

# ---------------- The kernel's GHC ----------------
GHC_BIN="$(command -v ghc)"
if [ "$KERNEL_GHC_VERSION" != "current" ] && [ "$("$GHC_BIN" --numeric-version)" != "$KERNEL_GHC_VERSION" ]; then
  HASKELL_ROOT="$(readlink -f "${HASKELL_HOME:-/opt/haskell-stable}")"
  GHCUP="${HASKELL_ROOT}/.ghcup/bin/ghcup"
  if [ -x "$GHCUP" ]; then
    echo "📦 Installing GHC ${KERNEL_GHC_VERSION} for the kernel (the booth's ghc stays $("$GHC_BIN" --numeric-version))..."
    GHCUP_INSTALL_BASE_PREFIX="$HASKELL_ROOT" GHCUP_SKIP_UPDATE_CHECK=1 \
      "$GHCUP" install ghc "$KERNEL_GHC_VERSION"
    GHC_BIN="${HASKELL_ROOT}/.ghcup/ghc/${KERNEL_GHC_VERSION}/bin/ghc"
    [ -x "$GHC_BIN" ] || { echo "❌ ghcup installed no ghc at ${GHC_BIN}" >&2; exit 1; }
    chmod -R a+rX "${HASKELL_ROOT}/.ghcup/ghc/${KERNEL_GHC_VERSION}"
  else
    echo "⚠️  No ghcup to install GHC ${KERNEL_GHC_VERSION}; the kernel uses $("$GHC_BIN" --numeric-version)." >&2
  fi
fi
GHC_VERSION="$("$GHC_BIN" --numeric-version)"
GHC_LIBDIR="$("$GHC_BIN" --print-libdir)"
GHC_BIN_DIR="$(dirname "$GHC_BIN")"
VERSION_TAG="${IHASKELL_VERSION}-ghc${GHC_VERSION}"
PREFIX="/opt/ihaskell/ihaskell-${VERSION_TAG}"
IHASKELL_BIN="${PREFIX}/bin/ihaskell"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export DEBIAN_FRONTEND=noninteractive

# ---------------- Prebuilt ----------------
# Returns 1 (fall back to a source build) when no build is published for this
# IHaskell + GHC + Ubuntu + CPU; a checksum mismatch stops the setup instead.
install_prebuilt() {
  rm -rf "$PREFIX"
  cb_prebuilt_install ihaskell "$VERSION_TAG" native "$PREFIX" || return 1
  [ -x "$IHASKELL_BIN" ] || { echo "❌ The prebuilt IHaskell has no bin/ihaskell" >&2; exit 1; }

  # Runtime libraries; libmagic1 was renamed libmagic1t64 in Ubuntu 24.04.
  apt-get update
  apt-get install -y --no-install-recommends libzmq5 libmagic1t64 \
    || apt-get install -y --no-install-recommends libzmq5 libmagic1 \
    || { echo "❌ Could not install libzmq5 and libmagic" >&2; exit 1; }
  rm -rf /var/lib/apt/lists/*
}

# ---------------- Source build ----------------
# Same layout as the prebuilt one: the cabal store goes straight into $PREFIX (the binary
# looks up its data files there), then everything but those data files is dropped. The
# package index is downloaded to a scratch CABAL_DIR, not to root's home.
build_from_source() {
  echo "📦 Installing IHaskell build dependencies..."
  apt-get update
  apt-get install -y --no-install-recommends \
    pkg-config libmagic-dev libzmq3-dev libncurses-dev
  rm -rf /var/lib/apt/lists/*

  echo "📦 Building IHaskell ${IHASKELL_VERSION} for GHC ${GHC_VERSION} via cabal..."
  export CABAL_DIR="$TMP/cabal" PATH="${GHC_BIN_DIR}:${PATH}"
  cabal update
  rm -rf "$PREFIX"
  mkdir -p "$PREFIX/bin"
  cabal --store-dir="$PREFIX/store" install "ihaskell-${IHASKELL_VERSION}" \
    --installdir="$PREFIX/bin" --install-method=copy --overwrite-policy=always
  strip "$IHASKELL_BIN" || true

  # The executable links its Haskell libraries statically; only the data files are used.
  find "$PREFIX/store" -mindepth 1 -maxdepth 1 ! -name 'ghc-*' -exec rm -rf {} +
  find "$PREFIX"/store/ghc-* -mindepth 1 -maxdepth 1 ! -type d -exec rm -f {} +
  find "$PREFIX"/store/ghc-* -mindepth 2 -maxdepth 2 ! -name share -exec rm -rf {} +
  find "$PREFIX"/store/ghc-* -mindepth 1 -maxdepth 1 -type d -empty -delete
}

# ---------------- Install IHaskell ----------------
if ! install_prebuilt; then
  build_from_source
fi
chmod -R a+rX "$PREFIX"

if [ ! -x "${IHASKELL_BIN}" ]; then
  echo "❌ ihaskell binary not found at ${IHASKELL_BIN}" >&2
  exit 1
fi

# ---------------- Create kernelspec ----------------
# --ghclib points the kernel at the kernel's GHC; the path compiled into the binary is the
# one it was built against. The launcher puts that GHC first on PATH, for the ghc and
# ghc-pkg the kernel runs itself.
TMPKDIR="$TMP/kernel/haskell"
mkdir -p "${TMPKDIR}"

cat > "${TMPKDIR}/ihaskell-kernel" <<LAUNCHER
#!/bin/sh
export PATH="${GHC_BIN_DIR}:\$PATH"
exec "${IHASKELL_BIN}" kernel "\$1" --ghclib "${GHC_LIBDIR}" +RTS -M3g -N2 -RTS
LAUNCHER
chmod 0755 "${TMPKDIR}/ihaskell-kernel"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
cat > "${TMPKDIR}/kernel.json" <<KJSON
{
  "argv": ["${KDIR}/ihaskell-kernel", "{connection_file}"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "haskell",
  "metadata": {
    "kernel_info": {
      "description": "Haskell (IHaskell) Jupyter kernel"
    }
  }
}
KJSON

# The logo and kernel.js ship among the data files.
html_dir="$(find "$PREFIX/store" -path "*/ihaskell-${IHASKELL_VERSION}-*/share/html" -type d | head -1)"
if [ -n "$html_dir" ]; then
  cp "$html_dir/kernel.js" "${TMPKDIR}/" 2>/dev/null || true
  cp "$html_dir/logo-64x64.svg" "${TMPKDIR}/" 2>/dev/null || true
fi

# ---------------- Register kernelspec system-wide ----------------
echo "🧩 Registering Haskell kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
python -m jupyter kernelspec install "${TMPKDIR}" \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --replace \
  --name="${KERNEL_NAME}"

chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Haskell (IHaskell) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   IHaskell binary:  ${IHASKELL_BIN} (GHC ${GHC_VERSION})"
