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

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-vscode.sh"; then
    skip_setup "$SCRIPT_NAME" "code-server/VSCode not installed"
fi

trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Load environment from profile.d ----------------
# These set: PY_STABLE, PY_STABLE_VERSION, PY_SERIES, VENV_SERIES_DIR, PATH tweaks, etc.
# Guarded with -f rather than relying on `2>/dev/null || true` to swallow a
# missing file: bash 3.2 — what macOS ships — treats a `source` that cannot find
# its file as fatal and exits the shell outright, before the `|| true` is ever
# consulted. Booths run bash 5, where the old form was harmless; the difference
# only surfaces when a test runs this script on a Mac host.
[ -f /etc/profile.d/53-cb-python--profile.sh ] \
    && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

install_extensions \
    ms-toolsai.jupyter           \
    ms-toolsai.jupyter-keymap    \
    ms-toolsai.jupyter-renderers
