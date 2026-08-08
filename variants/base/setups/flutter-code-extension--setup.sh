#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# flutter-code-extension--setup.sh
# Root-only installer to bootstrap the Dart/Flutter VS Code extensions.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

# A script copied into a project's .booth/setups/ shadows the image's copy, but
# libs/ does not come with it -- so $SCRIPT_DIR/libs is simply absent on the very
# path the dev loop and the complex tests use. Prefer the sibling dir when it is
# there, fall back to the image's, which is the same convention the code
# extension helper below already follows.
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

# Dart-Code.flutter depends on Dart-Code.dart-code; install the language support
# first so the Flutter extension does not have to resolve it itself.
install_extensions Dart-Code.dart-code Dart-Code.flutter

echo "✅ Extension installation completed."
