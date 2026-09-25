#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# reversal-icons--setup.sh — Reversal icon theme (https://github.com/yeyushengfan258/Reversal-icon-theme)
# installed system-wide. It does not change the default icon theme (xfce-theme--setup.sh
# does); pick it in Settings → Appearance → Icons, or `booth--theme set icons Reversal-dark`.
#
# Usage: reversal-icons--setup.sh [REF] [COLOR]
#   REF    git commit/branch of Reversal-icon-theme  (default: pinned commit, no releases upstream)
#   COLOR  color variant(s), comma-separated: default|black|blue|brown|cyan|green|grey|
#          lightblue|orange|pink|purple|red|all      (default: default)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

REVERSAL_REF="${1:-2c8122287e3bad5a6bf860ddd8c7e3b78cf4d451}"
REVERSAL_COLORS="${2:-default}"

apt--install.sh curl ca-certificates

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "https://github.com/yeyushengfan258/Reversal-icon-theme/archive/${REVERSAL_REF}.tar.gz" \
  | tar -xz -C "$WORK_DIR" --strip-components=1
# The installer's help lists "default" as a color, but the plain variant is what
# it installs when -t is omitted; "-t default" looks for a nonexistent color dir.
COLOR_ARGS=()
if [[ "$REVERSAL_COLORS" != "default" ]]; then
  COLOR_ARGS=(-t ${REVERSAL_COLORS//,/ })
fi
(cd "$WORK_DIR" && ./install.sh -d /usr/share/icons "${COLOR_ARGS[@]}")

if ! compgen -G "/usr/share/icons/Reversal*" >/dev/null; then
  echo "❌ No Reversal icon theme found under /usr/share/icons" >&2
  exit 2
fi

echo "✅ Reversal icons ${REVERSAL_REF:0:12} (${REVERSAL_COLORS}) installed:"
ls -d /usr/share/icons/Reversal*
