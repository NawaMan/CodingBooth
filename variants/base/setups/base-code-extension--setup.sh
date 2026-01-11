#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# code-essentials-extension--setup.sh
# Root-only installer to bootstrap useful VS Code extensions for all users.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi


SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/workspace/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions                      \
  formulahendry.code-runner             \
  fabiospampinato.vscode-highlight      \
  streetsidesoftware.code-spell-checker \
  yzhang.markdown-all-in-one            \
  alefragnani.Bookmarks                 \
  christian-kohler.path-intellisense

echo "✅ Extension installation completed."
