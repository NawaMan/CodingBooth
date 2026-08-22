#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# scala-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the Almond Jupyter kernel for Scala.
# Almond uses Coursier to fetch the kernel launcher.
#
# Prereqs:
#   - scala--setup.sh already ran (JDK on PATH; JAVA_HOME set).
#   - python--setup.sh and notebook--setup.sh already ran.
#   - /etc/profile.d/53-cb-python--profile.sh should be sourced.
#   - curl available.

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
ALMOND_VERSION="${ALMOND_VERSION:-0.14.0-RC15}"
SCALA_VERSION="${SCALA_VERSION:-3.3.4}"
KERNEL_NAME="${KERNEL_NAME:-scala}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Scala ${SCALA_VERSION}}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v java >/dev/null 2>&1; then
  echo "❌ Java is not installed or not on PATH (required by Scala kernel)." >&2
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

# ---------------- Install Coursier (if not present) ----------------
if ! command -v cs >/dev/null 2>&1; then
  echo "📦 Installing Coursier..."
  curl -fL "https://github.com/coursier/launchers/raw/master/cs-$(uname -m)-pc-linux.gz" \
    | gzip -d > /usr/local/bin/cs
  chmod +x /usr/local/bin/cs
fi

# ---------------- Install Almond ----------------
echo "📦 Installing Almond ${ALMOND_VERSION} for Scala ${SCALA_VERSION}..."
ALMOND_LAUNCHER="$(mktemp)"

cs bootstrap \
  "sh.almond:scala-kernel_${SCALA_VERSION}:${ALMOND_VERSION}" \
  --default=true \
  -o "${ALMOND_LAUNCHER}" \
  --standalone

chmod +x "${ALMOND_LAUNCHER}"

# Move to a stable location
ALMOND_BIN="/usr/local/bin/almond"
mv "${ALMOND_LAUNCHER}" "${ALMOND_BIN}"

# ---------------- Register kernelspec ----------------
echo "🧩 Registering Scala kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
"${ALMOND_BIN}" --install \
  --jupyter-path "${JUPYTER_KERNEL_PREFIX}/share/jupyter" \
  --id "${KERNEL_NAME}" \
  --display-name "${KERNEL_DISPLAY_NAME}" \
  --force

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Scala (Almond) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   Almond binary:    ${ALMOND_BIN}"
echo "   Scala version:    ${SCALA_VERSION}"
echo "   Almond version:   ${ALMOND_VERSION}"
