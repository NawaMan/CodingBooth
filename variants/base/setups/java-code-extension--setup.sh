#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Minimal-but-robust IJava (Java) Jupyter kernel installer.
# - Finds a Jupyter-capable venv under /opt/venvs
# - Detects JAVA_HOME or java/jshell on PATH
# - Installs IJava system-wide and (if possible) into the venv's sys-prefix
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-vscode.sh"; then
    skip_setup "$SCRIPT_NAME" "code-server/VSCode not installed"
fi

trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions                                      \
    redhat.java                                         \
    visualstudioexptteam.intellicode-api-usage-examples \
    visualstudioexptteam.vscodeintellicode              \
    vscjava.vscode-gradle                               \
    vscjava.vscode-java-debug                           \
    vscjava.vscode-java-dependency                      \
    vscjava.vscode-java-pack                            \
    vscjava.vscode-java-test                            \
    vscjava.vscode-maven                                \
    vscjava.vscode-lombok                               \
