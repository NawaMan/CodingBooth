#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# julia-code-extension--setup.sh
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

SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

# The extension ships a language server that resolves its own Julia packages the
# first time it activates, in the container rather than at build time. So the booth
# starts fast but the first Julia file opened pauses while LanguageServer.jl
# precompiles — expected, not a hang. Nothing to pre-warm here: that cache lives
# under the runtime user's depot, which does not exist yet during the build.
install_extensions julialang.language-julia

echo "✅ Extension installation completed."
