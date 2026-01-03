#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===================== Must be root =====================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

SETUPS_DIR=${SETUPS_DIR:-/opt/workspace/setups}
"${SETUPS_DIR}"/jetbrains--setup.sh pycharm
