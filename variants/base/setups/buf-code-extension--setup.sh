#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# buf-code-extension--setup.sh
# Root-only installer for the Buf VS Code extension (proto LSP, lint, format via the buf CLI).
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

# A copy in a project's .booth/setups/ shadows the image's script but brings no libs/
# with it, so fall back to the image's helpers (same convention as
# flutter-code-extension--setup.sh).
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
if [[ -r "$SCRIPT_DIR/libs/skip-setup.sh" ]]; then
    source "$SCRIPT_DIR/libs/skip-setup.sh"
else
    source "${SETUP_LIBS_DIR}/skip-setup.sh"
fi

CB_HAS_VSCODE="$SCRIPT_DIR/cb-has-vscode.sh"
[[ -x "$CB_HAS_VSCODE" ]] || CB_HAS_VSCODE=/opt/codingbooth/setups/cb-has-vscode.sh
if ! "$CB_HAS_VSCODE"; then
    skip_setup "$SCRIPT_NAME" "code-server/VSCode not installed"
fi

CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

# Same id on Open VSX (code-server) and the Marketplace (VS Code).
install_extensions bufbuild.vscode-buf

echo "✅ Extension installation completed."
