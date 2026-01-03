#!/usr/bin/env bash
# bash-code-extension--setup.sh
# Root-only installer for a login-time VS Code bootstrap in /etc/profile.d/.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi


SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/workspace/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions mads-hartmann.bash-ide-vscode
