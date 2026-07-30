#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# roc-code-extension--setup.sh
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

# There is no first-party Roc extension. This is the only one published, by an
# individual, and its own name says "unofficial" — which is why the template that
# calls this is the one language extension shipped opt-in (auto-select = false)
# rather than on by default. Revisit if roc-lang ever publishes its own.
install_extensions IvanDemchenko.roc-lang-unofficial

echo "✅ Extension installation completed."
