#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# gruppled-cursors--setup.sh — Gruppled Cursors by Craig Laparo (https://www.xfce-look.org/p/999974),
# prebuilt White and Black variants installed system-wide. It does not change the
# default cursor (xfce-theme--setup.sh does); pick it in Settings → Mouse and
# Touchpad → Theme, or `booth--theme set cursor gruppled_white`.
#
# The pling download link is a signed, expiring URL, so this fetches the GitHub
# re-upload instead (verified byte-identical to the pling tarball). The cursors
# only carry a 40px image; at another size Xcursor uses that nearest one.
#
# Usage: gruppled-cursors--setup.sh [VARIANTS] [REF]
#   VARIANTS  comma-separated: white,black  (default: white,black)
#   REF       git commit of nim65s/gruppled-cursors (default: pinned commit)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

VARIANTS="${1:-white,black}"
GRUPPLED_REF="${2:-78cc51eea14b9f4f35c25e51b7a6b4e0e1259e0e}"

apt--install.sh curl ca-certificates

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "https://github.com/nim65s/gruppled-cursors/archive/${GRUPPLED_REF}.tar.gz" \
  | tar -xz -C "$WORK_DIR" --strip-components=1

for variant in ${VARIANTS//,/ }; do
  theme="gruppled_${variant}"
  if [[ ! -d "$WORK_DIR/$theme/cursors" ]]; then
    echo "❌ Unknown variant '$variant' (white|black)" >&2
    exit 1
  fi
  rm -rf "/usr/share/icons/$theme"
  cp -r "$WORK_DIR/$theme" "/usr/share/icons/$theme"
done

echo "✅ Gruppled cursors (${VARIANTS}) installed:"
ls -d /usr/share/icons/gruppled_*
