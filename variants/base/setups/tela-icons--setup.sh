#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# tela-icons--setup.sh — Tela icon theme (https://github.com/vinceliuice/Tela-icon-theme)
# installed system-wide: Tela, Tela-light, Tela-dark (for the standard color).
# Install only — the default icon theme is xfce-theme--setup.sh's call; pick it
# in Settings → Appearance → Icons, or `booth--theme set icons Tela-dark`.
#
# Usage: tela-icons--setup.sh [VERSION] [COLOR]
#   VERSION  git tag of Tela-icon-theme   (default: 2026-07-07)
#   COLOR    installer color variant      (default: standard)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

TELA_VERSION="${1:-2026-07-07}"
TELA_COLOR="${2:-standard}"

apt--install.sh curl ca-certificates xz-utils

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "https://github.com/vinceliuice/Tela-icon-theme/archive/refs/tags/${TELA_VERSION}.tar.gz" \
  | tar -xz -C "$WORK_DIR" --strip-components=1
(cd "$WORK_DIR" && ./install.sh -d /usr/share/icons "$TELA_COLOR")

if ! compgen -G "/usr/share/icons/Tela*" >/dev/null; then
  echo "❌ No Tela icon theme found under /usr/share/icons" >&2
  exit 2
fi

echo "✅ Tela icons ${TELA_VERSION} (${TELA_COLOR}) installed"
