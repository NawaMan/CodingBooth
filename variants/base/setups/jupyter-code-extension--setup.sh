#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# jupyter-code-extension--setup.sh
# Root-only installer for Jupyter-related VS Code extensions.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

trap 'echo "❌ Error on line $LINENO"; exit 1' ERR


SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/coding-booth/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions \
    ms-toolsai.jupyter           \
    ms-toolsai.jupyter-keymap    \
    ms-toolsai.jupyter-renderers
