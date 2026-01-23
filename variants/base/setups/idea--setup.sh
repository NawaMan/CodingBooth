#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===================== Must be root =====================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    echo "SKIP: $SCRIPT_NAME - desktop environment not available" >&2
    exit 42
fi

SETUPS_DIR=${SETUPS_DIR:-/opt/codingbooth/setups}
"${SETUPS_DIR}"/jetbrains--setup.sh idea
