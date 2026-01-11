#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Install the IJava (Java) Jupyter kernel so BOTH:
#   1) a standalone Jupyter, and
#   2) code-server's Jupyter extension
# can see it.
#
# No CLI args. It auto-detects the venv and JDK, or errors out with guidance.
#
# Env you MAY set:
#   IJAVA_VERSION         -> IJava release tag (default: 1.3.0)
#   JUPYTER_KERNEL_PREFIX -> Where to install the kernelspec (default: /usr/local)
#   KERNEL_NAME           -> internal kernelspec name (folder) (default: java)
#   KERNEL_DISPLAY_NAME   -> user-facing name shown in picker (default: Java--${WS_JDK_VERSION})
#
# Prereqs:
#   - JDK installed (JAVA_HOME set; java/jshell on PATH).
#   - Target venv already has Jupyter (jupyter_client & jupyter_core present).
#   - curl, unzip available.
#   - Running under a venv; WS_VENV_DIR and WS_JDK_VERSION set.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "${EUID}" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

if [[ "${WS_VARIANT_TAG:-}" == "base" ]]; then
  echo "Variant does not include VS Code (code) or CodeServer" >&2
  exit 0
fi

if [[ "${WS_JDK_VERSION:-}" == "" ]]; then
  echo "JDK is not properly installed (WS_JDK_VERSION is not given)." >&2
  exit 1
fi
if [[ "$WS_JDK_VERSION" =~ ^[0-9]+$ ]] && [ "$WS_JDK_VERSION" -lt 9 ]; then
  echo "JDK version is less than 9 which notebook does not support."
  exit 1
fi



# ---------------- Source helpful profiles ----------------
source /etc/profile.d/53-ws-python--profile.sh
source /etc/profile.d/60-ws-jdk--profile.sh

# ---------------- Defaults / Tunables ----------------
IJAVA_VERSION="${IJAVA_VERSION:-1.3.0}"                         # default IJava tag
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"    # system-wide install
KERNEL_NAME="${KERNEL_NAME:-java}"                               # folder name (must be "java" for stock install.py)
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Java (${WS_JDK_VERSION})}"
WORKDIR="${WORKDIR:-/opt/ijava}"
TMPDIR="$(mktemp -d)"

# ---------------- Basic sanity ----------------
command -v python >/dev/null 2>&1 || { echo "❌ python not found." >&2; exit 2; }
command -v javac  >/dev/null 2>&1 || { echo "❌ javac not found (JDK not installed?)." >&2; exit 2; }

# Ensure chosen python has jupyter_client and jupyter_core
if ! python - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if all(u.find_spec(m) for m in ("jupyter_client","jupyter_core")) else 1)
PY
then
  echo "❌ python lacks required Jupyter packages ('jupyter_client' and/or 'jupyter_core')." >&2
  exit 2
fi

# Require JAVA_HOME for pinning the JVM in argv[0]
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
  echo "❌ JAVA_HOME is not set to a JDK (expected ${JAVA_HOME}/bin/java)." >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive

# ---------------- Fetch IJava release ----------------
mkdir -p "${WORKDIR}"
ZIP_URL="https://github.com/SpencerPark/IJava/releases/download/v${IJAVA_VERSION}/ijava-${IJAVA_VERSION}.zip"
echo "⬇️  Downloading IJava ${IJAVA_VERSION} …"
curl -fsSL "${ZIP_URL}" -o "${TMPDIR}/ijava.zip"
unzip -q -o "${TMPDIR}/ijava.zip" -d "${TMPDIR}"

INSTALL_PY="$(find "${TMPDIR}" -maxdepth 2 -type f -name 'install.py' -print -quit || true)"
if [ -z "${INSTALL_PY}" ]; then
  echo "❌ IJava archive did not contain install.py. Aborting." >&2
  exit 1
fi

# Stage into a stable location for reuse
src_dir="$(dirname "${INSTALL_PY}")"
mkdir -p "${WORKDIR}"

# Emulate rsync --delete: remove existing contents of WORKDIR
find "${WORKDIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

cp -a "${src_dir}/." "${WORKDIR}/"
chmod -R a+rX "${WORKDIR}"

# ---------------- Adjust the template BEFORE install ----------------
# We edit the staged template at ${WORKDIR}/java/kernel.json so display_name & JAVA_HOME are baked in.
KDIR="${WORKDIR}/java"
KJSON="${KDIR}/kernel.json"

if [ ! -f "${KJSON}" ]; then
  echo "❌ Template kernel.json not found at ${KJSON}" >&2
  exit 1
fi

echo "🛠  Stamping template kernel.json (display_name='${KERNEL_DISPLAY_NAME}', JAVA_HOME='${JAVA_HOME}')"
python - "${KJSON}" "${KERNEL_DISPLAY_NAME}" "${JAVA_HOME}" <<'PY'
import json, os, sys
JSON, DISPLAY_NAME, JAVA_HOME = sys.argv[1], sys.argv[2], sys.argv[3]
with open(JSON) as f:
    data = json.load(f)

# 1) Set display_name in the TEMPLATE (this persists into the installed spec)
data["display_name"] = DISPLAY_NAME

# 2) Pin JAVA_HOME in env for clarity
env = data.get("env", {})
env["JAVA_HOME"] = JAVA_HOME
data["env"] = env

# 3) If argv[0] is "java", replace it with JAVA_HOME/bin/java so the chosen JDK is used.
argv = data.get("argv", [])
if argv and argv[0] == "java":
    data["argv"][0] = os.path.join(JAVA_HOME, "bin", "java")

with open(JSON, "w") as f:
    json.dump(data, f, indent=2)
PY

# ---------------- Register system-wide ----------------
echo "🧩 Registering IJava kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide) …"
pushd "${WORKDIR}" >/dev/null

# Use upstream install.py as-is. It supports --user/--sys-prefix/--prefix and --replace.
# We pass --prefix so both Jupyter and code-server can see it under ${JUPYTER_KERNEL_PREFIX}.
python install.py \
  --prefix "${JUPYTER_KERNEL_PREFIX}" \
  --replace

# Move from the installed location to the target one where the folder name will be the kernel name 
#    so that the kernel name will reflect the version.
INSTALLED_KERNEL_DIR=${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/java
TARGET_KERNEL_DIR=${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/java${WS_JDK_VERSION}

if [[ -d "${TARGET_KERNEL_DIR}" ]]; then
    rm -Rf "${TARGET_KERNEL_DIR}"
fi
mv "${INSTALLED_KERNEL_DIR}" "${TARGET_KERNEL_DIR}"
sed -i "s|${INSTALLED_KERNEL_DIR}|${TARGET_KERNEL_DIR}|g" "${TARGET_KERNEL_DIR}/kernel.json"

popd >/dev/null

# ---------------- Verification ----------------
echo
echo "🔎 Kernels (current python):"
python -m jupyter kernelspec list || true

echo
echo "✅ IJava template was at: ${KDIR}"
echo "   Installed under:      ${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
echo "   Display name:         ${KERNEL_DISPLAY_NAME}"
echo "   JAVA_HOME:            ${JAVA_HOME}"
echo "   Python used:          ${WS_VENV_DIR:-<unknown>}/bin/python"
echo "   WS_VENV_DIR:          ${WS_VENV_DIR:-<unknown>}"
