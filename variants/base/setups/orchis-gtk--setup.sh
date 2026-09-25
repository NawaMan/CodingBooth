#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# orchis-gtk--setup.sh — Orchis GTK theme (https://github.com/vinceliuice/Orchis-theme),
# GTK 2/3/4 + xfwm4 window decorations, installed system-wide.
#
# Install only; pick it in Settings → Appearance and Window Manager, or
# `booth--theme set gtk Orchis-Dark`.
#
# Usage: orchis-gtk--setup.sh [ACCENT] [SIZE] [VERSION]
#   ACCENT         comma-separated: default|purple|pink|red|orange|yellow|green|
#                  teal|grey|all                                    (default: default, i.e. blue)
#   SIZE           standard | compact | all                         (default: standard)
#   VERSION        git tag of Orchis-theme                          (default: 2026-07-07)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

ACCENTS="${1:-default}"
SIZE="${2:-standard}"
ORCHIS_VERSION="${3:-2026-07-07}"

# sassc compiles the theme's CSS; murrine renders the GTK2 part.
apt--install.sh curl ca-certificates sassc gtk2-engines-murrine

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "https://github.com/vinceliuice/Orchis-theme/archive/refs/tags/${ORCHIS_VERSION}.tar.gz" \
  | tar -xz -C "$WORK_DIR" --strip-components=1

SIZE_ARGS=()
if [[ "$SIZE" != "all" ]]; then
  SIZE_ARGS=(-s "$SIZE")
fi
(cd "$WORK_DIR" && ./install.sh -d /usr/share/themes -t ${ACCENTS//,/ } "${SIZE_ARGS[@]}")

if ! compgen -G "/usr/share/themes/Orchis*/xfwm4" >/dev/null; then
  echo "❌ No Orchis theme with xfwm4 decorations found under /usr/share/themes" >&2
  exit 2
fi

echo "✅ Orchis ${ORCHIS_VERSION} installed"
ls -d /usr/share/themes/Orchis*
