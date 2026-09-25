#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# vscode-copilot--setup.sh — put GitHub Copilot back into a VS Code that
# vscode--setup.sh stripped it from (the default, to save ~290 MB).
#
# Restores exactly the two folders that were removed, taken from the same
# `code` version's .deb, rather than reinstalling the package: a reinstall
# would also overwrite the desktop launchers vscode--setup.sh points at the
# booth's /usr/local/bin/code wrapper. Also drops the stripped marker, so the
# wrapper stops seeding "chat.disableAIFeatures": true for new homes.
#
# Usage: vscode-copilot--setup.sh
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! dpkg-query -W code &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "VS Code is not installed (it comes with the desktop variants)"
fi

MARKER=/etc/codingbooth/vscode-copilot-stripped
VSCODE_APP=/usr/share/code/resources/app
if [[ ! -f "$MARKER" ]]; then
  echo "✅ VS Code already has GitHub Copilot — nothing to restore"
  exit 0
fi

VERSION="$(dpkg-query -W -f='${Version}' code)"
export DEBIAN_FRONTEND=noninteractive

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Refresh only Microsoft's repo — the image's lists were cleaned after build.
apt-get update \
  -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/vscode.list \
  -o Dir::Etc::sourceparts=- \
  -o APT::Get::List-Cleanup=0
(cd "$WORK_DIR" && apt-get download "code=${VERSION}")
dpkg-deb -x "$WORK_DIR"/code_*.deb "$WORK_DIR/root"

SRC_APP="$WORK_DIR/root$VSCODE_APP"
if [[ ! -d "$SRC_APP/extensions/copilot" ]]; then
  echo "❌ code ${VERSION} has no built-in Copilot extension to restore" >&2
  exit 2
fi
rm -rf "$VSCODE_APP/extensions/copilot"
cp -a "$SRC_APP/extensions/copilot" "$VSCODE_APP/extensions/"
for sdk in "$SRC_APP"/node_modules.asar.unpacked/@github/copilot-sdk-*; do
  [[ -d "$sdk" ]] || continue
  mkdir -p "$VSCODE_APP/node_modules.asar.unpacked/@github"
  rm -rf "$VSCODE_APP/node_modules.asar.unpacked/@github/$(basename "$sdk")"
  cp -a "$sdk" "$VSCODE_APP/node_modules.asar.unpacked/@github/"
done

rm -f "$MARKER"
echo "✅ GitHub Copilot restored to VS Code ${VERSION}"
