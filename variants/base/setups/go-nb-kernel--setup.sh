#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# go-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the GoNB (Go Notebook) Jupyter kernel.
# GoNB provides a full Go REPL experience in Jupyter.
#
# Prereqs:
#   - go--setup.sh already ran successfully (Go on PATH, GOPATH set).
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
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-go}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Go (GoNB)}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "❌ Go is not installed or not on PATH." >&2
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

# ---------------- Install GoNB ----------------
echo "📦 Installing GoNB kernel binary..."
go install github.com/janpfeifer/gonb@latest
go install golang.org/x/tools/cmd/goimports@latest

GONB_BIN="$(go env GOPATH)/bin/gonb"
if [ ! -x "${GONB_BIN}" ]; then
  echo "❌ gonb binary not found at ${GONB_BIN}" >&2
  exit 1
fi

# ---------------- Create kernelspec manually ----------------
# We create the kernelspec ourselves rather than relying on `gonb --install`
# which writes to the user's jupyter data dir, not our system prefix.
TMPKDIR="$(mktemp -d)/gonb"
mkdir -p "${TMPKDIR}"

cat > "${TMPKDIR}/kernel.json" <<KJSON
{
  "argv": ["${GONB_BIN}", "--kernel", "{connection_file}"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "go",
  "metadata": {
    "kernel_info": {
      "description": "Go (GoNB) Jupyter kernel"
    }
  }
}
KJSON

# ---------------- Register kernelspec system-wide ----------------
echo "🧩 Registering Go kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
python -m jupyter kernelspec install "${TMPKDIR}" \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --replace \
  --name="${KERNEL_NAME}"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Go (GoNB) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   GoNB binary:      ${GONB_BIN}"
