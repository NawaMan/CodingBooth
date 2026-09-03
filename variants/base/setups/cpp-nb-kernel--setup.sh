#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# cpp-nb-kernel--setup.sh
#
# ⚠️  EXPERIMENTAL / UNTESTED
# This script installs the xeus-cling C++ Jupyter kernel via conda-forge.
# xeus-cling is upstream-unmaintained, may not build against newer LLVMs,
# and may produce unstable behavior. Please report success/failure.
#
# Prereqs:
#   - python--setup.sh and notebook--setup.sh already ran.
#   - conda or miniforge available (we install a minimal mamba/micromamba on the fly
#     into /opt/xeus-cling-env if not present).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
ENV_PREFIX="/opt/xeus-cling-env"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter (need python+notebook installed first)." >&2
  exit 1
fi

if ! python - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if all(u.find_spec(m) for m in ("jupyter_client","jupyter_core")) else 1)
PY
then
  echo "❌ python lacks Jupyter packages ('jupyter_client'/'jupyter_core')." >&2
  exit 2
fi

# ---------------- Bootstrap micromamba if no conda-like tool exists ----------------
MAMBA_BIN=""
for cand in micromamba mamba conda; do
  if command -v "$cand" >/dev/null 2>&1; then
    MAMBA_BIN="$(command -v "$cand")"
    break
  fi
done

if [[ -z "$MAMBA_BIN" ]]; then
  echo "📦 Bootstrapping micromamba into /usr/local/bin ..."
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  MM_ARCH="linux-64" ;;
    aarch64) MM_ARCH="linux-aarch64" ;;
    *) echo "❌ Unsupported arch: $ARCH"; exit 1 ;;
  esac

  # micromamba is shipped as a tar.bz2 — make sure curl/tar/bzip2/ca-certificates
  # are present (they are NOT guaranteed in slimmer base images).
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar bzip2
  rm -rf /var/lib/apt/lists/*

  curl --retry 3 --retry-delay 2 -fsSL "https://micro.mamba.pm/api/micromamba/${MM_ARCH}/latest" \
    | tar -xj -C /tmp bin/micromamba
  install -m 0755 /tmp/bin/micromamba /usr/local/bin/micromamba
  MAMBA_BIN=/usr/local/bin/micromamba
fi

# ---------------- Install xeus-cling into a dedicated env ----------------
echo "📦 Installing xeus-cling into ${ENV_PREFIX} (this can be slow) ..."
case "$(basename "$MAMBA_BIN")" in
  micromamba)
    "$MAMBA_BIN" create -y -p "$ENV_PREFIX" -c conda-forge xeus-cling jupyter_client
    ;;
  *)
    "$MAMBA_BIN" create -y -p "$ENV_PREFIX" -c conda-forge xeus-cling jupyter_client
    ;;
esac

# ---------------- Register kernelspecs system-wide ----------------
# xeus-cling installs its kernelspecs under $ENV_PREFIX/share/jupyter/kernels/{xcpp14,xcpp17,xcpp20}
SRC_KERNELS_DIR="${ENV_PREFIX}/share/jupyter/kernels"
DEST_KERNELS_DIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels"
install -d "$DEST_KERNELS_DIR"

REGISTERED=0
if [[ -d "$SRC_KERNELS_DIR" ]]; then
  for k in "$SRC_KERNELS_DIR"/xcpp*; do
    [[ -d "$k" ]] || continue
    name="$(basename "$k")"
    rm -rf "${DEST_KERNELS_DIR}/${name}"
    cp -a "$k" "${DEST_KERNELS_DIR}/${name}"
    REGISTERED=$((REGISTERED + 1))
  done
fi

if [[ $REGISTERED -eq 0 ]]; then
  echo "❌ No xcpp kernels found under ${SRC_KERNELS_DIR}; install probably failed." >&2
  exit 1
fi

chmod -R a+rX "$DEST_KERNELS_DIR" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels registered system-wide:"
python -m jupyter kernelspec list || true

echo
echo "✅ xeus-cling C++ kernels installed (${REGISTERED} kernel(s))."
echo "   Env prefix:    ${ENV_PREFIX}"
echo "   Kernels dir:   ${DEST_KERNELS_DIR}"
echo "⚠️  Reminder: this kernel is EXPERIMENTAL and may break with newer toolchains."
