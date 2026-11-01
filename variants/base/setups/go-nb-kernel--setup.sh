#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.2.0

# go-nb-kernel--setup.sh
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

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>]

Examples:
  $0                       # GoNB ${GONB_DEFAULT_VER:-0.11.5}
  $0 --version 0.11.4      # pin a release

Notes:
- Installs gonb to /usr/local/bin and registers the "go" kernel system-wide
- Comes prebuilt (sha256-checked) from https://github.com/NawaMan/CodingBoothPrebuilt
  on both CPUs (upstream publishes source only); a version not prebuilt (yet) is
  built with \`go install\` into the booth user's ~/go/bin
- goimports, which GoNB runs on every cell, is installed with \`go install\`
USAGE
}

GONB_DEFAULT_VER="0.11.5"
VERSION="$GONB_DEFAULT_VER"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; VERSION="${1:-}"; shift || true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a GoNB version: '${VERSION}' (expected X.Y.Z, for example ${GONB_DEFAULT_VER})" >&2
  exit 2
fi

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Load environment from profile.d ----------------
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-go}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Go (GoNB)}"
# The user GoNB is installed for: 'coder' in a booth; the real user when
# provisioning a machine or a runner (see docs/REUSE_BOOTH.md).
CB_USER_NAME="${CB_USER_NAME:-coder}"
# The home is the account's own, not assumed to be /home/<name>.
CB_USER_HOME="${CB_USER_HOME:-$(getent passwd "$CB_USER_NAME" 2>/dev/null | cut -d: -f6 || true)}"
CB_USER_HOME="${CB_USER_HOME:-/home/${CB_USER_NAME}}"

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
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

echo "📦 Installing GoNB ${VERSION} kernel binary..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if cb_prebuilt_install gonb "$VERSION" native "$TMP/prebuilt"; then
  install -m 755 "$TMP/prebuilt/bin/gonb" /usr/local/bin/gonb
  GONB_BIN=/usr/local/bin/gonb
else
  echo "ℹ️  GoNB ${VERSION}: not prebuilt for this image; building with go install..."
  sudo -u "$CB_USER_NAME" bash -lc "go install github.com/janpfeifer/gonb@v${VERSION}"
  GONB_BIN="${CB_USER_HOME}/go/bin/gonb"
fi
sudo -u "$CB_USER_NAME" bash -lc "go install golang.org/x/tools/cmd/goimports@latest"

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
