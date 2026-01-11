#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Install the JJava (Java) Jupyter kernel so BOTH:
#   1) a standalone Jupyter, and
#   2) code-server's Jupyter extension
# can see it.
#
# No CLI args. It auto-detects the venv and JDK, or errors out with guidance.
#
# Env you MAY set:
#   JJAVA_VERSION         -> JJava GitHub release tag (default: 1.0-M1)
#   JUPYTER_KERNEL_PREFIX -> Where to install the kernelspec (default: /usr/local)
#   KERNEL_NAME           -> internal kernelspec name (folder before optional rename) (default: java)
#   KERNEL_DISPLAY_NAME   -> user-facing name shown in picker (default: Java (${WS_JDK_VERSION}))
#
# Optional JJava env vars to bake into kernel.json "env":
#   JJAVA_JVM_OPTS
#   JJAVA_COMPILER_OPTS
#   JJAVA_CLASSPATH
#   JJAVA_STARTUP_SCRIPT
#   JJAVA_STARTUP_SCRIPTS_PATH
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
  echo "❌ JDK is not properly installed (WS_JDK_VERSION is not given)." >&2
  exit 1
fi
if [[ "$WS_JDK_VERSION" =~ ^[0-9]+$ ]] && [ "$WS_JDK_VERSION" -lt 11 ]; then
  echo "❌ JDK version is less than 11; JJava requires Java 11+." >&2
  exit 1
fi

# ---------------- Source helpful profiles ----------------
source /etc/profile.d/53-ws-python--profile.sh
source /etc/profile.d/60-ws-jdk--profile.sh

# ---------------- Defaults / Tunables ----------------
JJAVA_VERSION="${JJAVA_VERSION:-1.0-a6}"                        # default JJava tag (GitHub Release tag)
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"    # system-wide install
KERNEL_NAME="${KERNEL_NAME:-java}"                              # kernelspec name (initial install name)
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Java (${WS_JDK_VERSION})}"
WORKDIR="${WORKDIR:-/opt/jjava}"
TMPDIR="$(mktemp -d)"

# ---------------- Basic sanity ----------------
command -v python >/dev/null 2>&1 || { echo "❌ python not found." >&2; exit 2; }
command -v javac  >/dev/null 2>&1 || { echo "❌ javac not found (JDK not installed?)." >&2; exit 2; }
command -v curl   >/dev/null 2>&1 || { echo "❌ curl not found." >&2; exit 2; }
command -v unzip  >/dev/null 2>&1 || { echo "❌ unzip not found." >&2; exit 2; }

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

# ---------------- Fetch JJava release ----------------
mkdir -p "${WORKDIR}"

# GitHub release tags are typically like "1.0-M1" (no leading "v"). If user passes "vX", strip it.
JJAVA_TAG="${JJAVA_VERSION#v}"

ZIP_URL="https://github.com/dflib/jjava/releases/download/${JJAVA_TAG}/jjava-${JJAVA_TAG}-kernelspec.zip"
echo "⬇️  Downloading JJava ${JJAVA_TAG} …"
curl -fsSL "${ZIP_URL}" -o "${TMPDIR}/jjava-kernelspec.zip"

unzip -q -o "${TMPDIR}/jjava-kernelspec.zip" -d "${TMPDIR}"

# Find the unzipped kernelspec directory (should contain kernel.json + jars)
KERNELSRC="$(find "${TMPDIR}" -maxdepth 3 -type f -name 'kernel.json' -print -quit || true)"
if [ -z "${KERNELSRC}" ]; then
  echo "❌ JJava archive did not contain kernel.json. Aborting." >&2
  exit 1
fi
src_dir="$(dirname "${KERNELSRC}")"

# Basic validation that this looks like JJava
if [ ! -f "${src_dir}/jjava.jar" ] || [ ! -f "${src_dir}/jjava-launcher.jar" ]; then
  echo "❌ The unzipped folder does not look like a JJava kernelspec (missing jjava.jar / jjava-launcher.jar)." >&2
  echo "   Found kernelspec dir: ${src_dir}" >&2
  exit 1
fi

# Stage into a stable location for reuse
mkdir -p "${WORKDIR}"
find "${WORKDIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "${src_dir}/." "${WORKDIR}/"
chmod -R a+rX "${WORKDIR}"

# ---------------- Adjust kernel.json BEFORE install ----------------
KJSON="${WORKDIR}/kernel.json"
if [ ! -f "${KJSON}" ]; then
  echo "❌ kernel.json not found at ${KJSON}" >&2
  exit 1
fi

echo "🛠  Stamping kernel.json (display_name='${KERNEL_DISPLAY_NAME}', JAVA_HOME='${JAVA_HOME}')"
python - "${KJSON}" "${KERNEL_DISPLAY_NAME}" "${JAVA_HOME}" <<'PY'
import json, os, sys

JSON_PATH, DISPLAY_NAME, JAVA_HOME = sys.argv[1], sys.argv[2], sys.argv[3]

with open(JSON_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

# 1) Set display_name
data["display_name"] = DISPLAY_NAME

# 2) Pin JAVA_HOME and optionally pass through JJAVA_* env vars
env = data.get("env", {}) or {}
env["JAVA_HOME"] = JAVA_HOME

for k in (
    "JJAVA_JVM_OPTS",
    "JJAVA_COMPILER_OPTS",
    "JJAVA_CLASSPATH",
    "JJAVA_STARTUP_SCRIPT",
    "JJAVA_STARTUP_SCRIPTS_PATH",
):
    v = os.environ.get(k)
    if v:
        env[k] = v

data["env"] = env

# 3) If argv[0] is "java", replace it with JAVA_HOME/bin/java so the chosen JDK is used.
argv = data.get("argv", []) or []
if argv and argv[0] == "java":
    argv[0] = os.path.join(JAVA_HOME, "bin", "java")
data["argv"] = argv

with open(JSON_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

# ---------------- Register system-wide ----------------
echo "🧩 Registering JJava kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide) …"

# Use python -m jupyter to guarantee we're using the same python environment we validated above.
python -m jupyter kernelspec install "${WORKDIR}" \
  --prefix "${JUPYTER_KERNEL_PREFIX}" \
  --replace \
  --name "${KERNEL_NAME}"

# ---------------- Rename kernel folder to include JDK version (match existing IJava behavior) ----------------
INSTALLED_KERNEL_DIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
TARGET_KERNEL_DIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/java${WS_JDK_VERSION}"

if [[ ! -d "${INSTALLED_KERNEL_DIR}" ]]; then
  echo "❌ Expected installed kernel dir not found: ${INSTALLED_KERNEL_DIR}" >&2
  exit 1
fi

if [[ -d "${TARGET_KERNEL_DIR}" ]]; then
  rm -rf "${TARGET_KERNEL_DIR}"
fi
mv "${INSTALLED_KERNEL_DIR}" "${TARGET_KERNEL_DIR}"
chmod -R a+rX "${TARGET_KERNEL_DIR}"

# ---------------- Patch kernel.json after move ----------------
# Two things:
#  1) Fix any hard paths that might still reference the old folder (rare, but safe)
#  2) Replace {resource_dir} with the absolute directory path for better VS Code / code-server compatibility
#     (some environments have issues resolving {resource_dir} placeholders).
echo "🧩 Finalizing kernel.json for relocated install dir…"
python - "${TARGET_KERNEL_DIR}/kernel.json" "${TARGET_KERNEL_DIR}" "${JAVA_HOME}" <<'PY'
import json, os, sys

JSON_PATH, RESOURCE_DIR, JAVA_HOME = sys.argv[1], sys.argv[2], sys.argv[3]

with open(JSON_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

argv = data.get("argv", []) or []
new_argv = []
for a in argv:
    if isinstance(a, str):
        a = a.replace("{resource_dir}", RESOURCE_DIR)
        # In case any prior absolute path had the old location embedded, normalize known Jupyter token.
        # (We don't know the old path here; the resource_dir replacement handles most issues.)
    new_argv.append(a)
data["argv"] = new_argv

env = data.get("env", {}) or {}
# Keep JAVA_HOME pinned; re-assert to be safe.
env["JAVA_HOME"] = JAVA_HOME
data["env"] = env

with open(JSON_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

# ---------------- Verification ----------------
echo
echo "🔎 Kernels (current python):"
python -m jupyter kernelspec list || true

echo
echo "✅ JJava kernelspec staged at: ${WORKDIR}"
echo "   Installed under:          ${TARGET_KERNEL_DIR}"
echo "   Kernel name (installed):  java${WS_JDK_VERSION}"
echo "   Display name:             ${KERNEL_DISPLAY_NAME}"
echo "   JAVA_HOME:                ${JAVA_HOME}"
echo "   Python used:              ${WS_VENV_DIR:-<unknown>}/bin/python"
echo "   WS_VENV_DIR:              ${WS_VENV_DIR:-<unknown>}"
