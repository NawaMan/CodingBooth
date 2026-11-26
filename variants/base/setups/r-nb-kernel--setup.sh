#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

# r-nb-kernel--setup.sh
#
# Installs the IRkernel Jupyter kernel for R.
# IRkernel is the official R kernel for Jupyter.
#
# Prereqs:
#   - r-rscript--setup.sh already ran successfully (R/Rscript on PATH).
#   - python--setup.sh and notebook--setup.sh already ran.
#   - /etc/profile.d/53-cb-python--profile.sh should be sourced.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

# ---------------- Load environment from profile.d ----------------
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-ir}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-R}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v R >/dev/null 2>&1; then
  echo "❌ R is not installed or not on PATH." >&2
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

# ---------------- Install IRkernel R package ----------------
# Binaries from r2u (https://eddelbuettel.github.io/r2u/), not CRAN source. CRAN serves Linux
# packages as source, so install.packages() compiled IRkernel's C dependencies (pbdZMQ, uuid,
# digest, base64enc, jsonlite) in every image. Ubuntu's own r-cran-* packages do not help:
# they are built against Ubuntu's R, and r-rscript installs CRAN's newer R (4.6 removed
# SETLENGTH, which Ubuntu's base64enc still calls). r2u publishes every CRAN package as an apt
# package built against CRAN's current R, for amd64 and arm64, and is pinned here above
# Ubuntu's archive so apt takes its r-cran-* over Ubuntu's. Its signing key is checked
# against the fingerprint below. A release r2u does not cover falls back to CRAN source.
R2U_URL="https://r2u.stat.illinois.edu/ubuntu"
R2U_KEY_URL="https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc"
R2U_KEY_FPR="AE89DB0EE10E60C01100A8F2A1489FE2AB99A21A"
CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
export DEBIAN_FRONTEND=noninteractive

if [[ -n "$CODENAME" ]] && curl -fsSL --retry 3 --retry-delay 3 "${R2U_URL}/dists/${CODENAME}/Release" -o /dev/null 2>/dev/null; then
  echo "📦 Installing IRkernel (r-cran-irkernel) from r2u for ${CODENAME}..."
  KEY_TMP="$(mktemp -d)"
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "$R2U_KEY_URL" -o "$KEY_TMP/r2u.asc"
  GOT_FPR="$(gpg --show-keys --with-colons "$KEY_TMP/r2u.asc" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')"
  if [[ "$GOT_FPR" != "$R2U_KEY_FPR" ]]; then
    echo "❌ r2u signing key fingerprint is '${GOT_FPR:-none}', expected ${R2U_KEY_FPR}" >&2
    exit 1
  fi
  gpg --dearmor < "$KEY_TMP/r2u.asc" > /usr/share/keyrings/r2u.gpg
  rm -rf "$KEY_TMP"
  echo "deb [signed-by=/usr/share/keyrings/r2u.gpg] ${R2U_URL} ${CODENAME} main" > /etc/apt/sources.list.d/r2u.list
  cat > /etc/apt/preferences.d/99-r2u <<'PIN'
Package: *
Pin: release o=CRAN-Apt Project
Pin: release l=CRAN-Apt Packages
Pin-Priority: 700
PIN
  apt-get update
  apt-get install -y --no-install-recommends r-cran-irkernel
  rm -rf /var/lib/apt/lists/*
else
  echo "ℹ️  r2u has no packages for Ubuntu '${CODENAME:-?}'; building IRkernel from CRAN source..."
  R --slave -e "install.packages('IRkernel', repos='https://cloud.r-project.org', quiet=TRUE)"
fi
R --slave -e "invisible(packageVersion('IRkernel'))" \
  || { echo "❌ IRkernel was installed, but R cannot load it" >&2; exit 1; }

# ---------------- Register kernelspec ----------------
# IRkernel::installspec() natively supports prefix — very clean!
echo "🧩 Registering R kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
R --slave -e "IRkernel::installspec(name='${KERNEL_NAME}', displayname='${KERNEL_DISPLAY_NAME}', prefix='${JUPYTER_KERNEL_PREFIX}')"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ R (IRkernel) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
R_VER="$(R --version 2>/dev/null | head -1 || echo 'unknown')"
echo "   R version:        ${R_VER}"
