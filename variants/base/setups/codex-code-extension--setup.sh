#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# codex-code-extension--setup.sh
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

# OpenAI's VS Code extension (includes ChatGPT/Codex features)
EXT_ID="openai.chatgpt"

install_into_cli() {
  local cli="$1"
  local dir="$2"
  local bin="$3"
  local -a cli_opts=()

  mkdir -p "$dir"
  if [[ "$cli" == "code" && "${EUID}" -eq 0 ]]; then
    local vscode_root_data="/tmp/vscode-root-user-data"
    mkdir -p "$vscode_root_data"
    cli_opts=(--no-sandbox --user-data-dir "$vscode_root_data")
  fi

  # ${cli_opts[@]+"..."}: cli_opts is empty for every CLI but root-run `code`,
  # and under `set -u` bash 3.2 (macOS) treats a plain "${cli_opts[@]}" on an
  # empty array as unbound and aborts. Booths run bash 5; this shows only when a
  # test runs the script on a Mac host.
  echo "Installing ${EXT_ID} via ${bin} (extensions dir: ${dir})..."
  if "$bin" ${cli_opts[@]+"${cli_opts[@]}"} --extensions-dir "$dir" --install-extension "$EXT_ID"; then
    echo "  ✔ Install command succeeded"
  else
    echo "  ⚠ Install command failed for ${cli}" >&2
    return 1
  fi

  if "$bin" ${cli_opts[@]+"${cli_opts[@]}"} --extensions-dir "$dir" --list-extensions | grep -qx "$EXT_ID"; then
    echo "  ✔ Verified: ${EXT_ID}"
    return 0
  fi

  echo "  ⚠ Extension not found after install: ${EXT_ID}" >&2
  return 1
}

installed_any=0

if command -v code >/dev/null 2>&1; then
  # Prefer the real VS Code binary because /usr/local/bin/code can be a GUI wrapper.
  CODE_BIN="/usr/bin/code"
  [[ -x "$CODE_BIN" ]] || CODE_BIN="$(command -v code)"
  if install_into_cli "code" "$VSCODE_EXTENSION_DIR" "$CODE_BIN"; then
    installed_any=1
  fi
fi

if command -v code-server >/dev/null 2>&1; then
  # Note: this extension may be unavailable in some code-server marketplaces.
  install_into_cli "code-server" "$CODESERVER_EXTENSION_DIR" "$(command -v code-server)" || true
fi

if command -v code >/dev/null 2>&1 && [[ "$installed_any" -eq 0 ]]; then
  echo "ERROR: ${EXT_ID} was not verified in VS Code desktop." >&2
  exit 1
fi

if [[ "$installed_any" -eq 0 ]]; then
  echo "WARNING: VS Code desktop not found; skipped desktop verification for ${EXT_ID}." >&2
fi
