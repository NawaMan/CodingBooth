#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# octave-code-extension--setup.sh
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
source "${SETUP_LIBS_DIR}/skip-setup.sh"
if ! /opt/codingbooth/setups/cb-has-vscode.sh 2>/dev/null; then
    skip_setup "$SCRIPT_NAME" "code-server/VSCode not installed"
fi

CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions lucasfa.octaveexecution

echo "✅ Extension installation completed."
