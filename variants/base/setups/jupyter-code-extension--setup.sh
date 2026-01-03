#!/usr/bin/env bash
# jupyter-code-extension--setup.sh
# Root-only installer for Jupyter-related VS Code extensions.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

trap 'echo "❌ Error on line $LINENO"; exit 1' ERR


SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/workspace/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions \
    ms-toolsai.jupyter           \
    ms-toolsai.jupyter-keymap    \
    ms-toolsai.jupyter-renderers
