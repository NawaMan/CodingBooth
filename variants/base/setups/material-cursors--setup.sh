#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# material-cursors--setup.sh — Material Cursors (https://github.com/varlesh/material-cursors)
# built from source and installed system-wide.
#
# Upstream's build.sh renders the SVGs with Inkscape; this does the same render
# with rsvg-convert (far lighter) and then follows build.sh: xcursorgen per
# src/config/*.cursor, plus the alias symlinks from src/cursorList.
#
# Install only — the default cursor is xfce-theme--setup.sh's call; pick it in
# Settings → Mouse and Touchpad, or `booth--theme set cursor material_light_cursors`.
# Built sizes: 24, 32, 48, 64.
#
# Usage: material-cursors--setup.sh [VARIANT] [REF]
#   VARIANT  light | dark | default   (default: light)
#   REF      git commit of material-cursors (default: pinned commit, no releases upstream)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

VARIANT="${1:-light}"
MC_REF="${2:-2a5f302fefe04678c421473bed636b4d87774b4a}"

case "$VARIANT" in
  light)   THEME="material_light_cursors" ;;
  dark)    THEME="material_dark_cursors"  ;;
  default) THEME="material_cursors"       ;;
  *) echo "❌ Unknown variant '$VARIANT' (light|dark|default)" >&2; exit 1 ;;
esac

apt--install.sh curl ca-certificates librsvg2-bin x11-apps

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "https://github.com/varlesh/material-cursors/archive/${MC_REF}.tar.gz" \
  | tar -xz -C "$WORK_DIR" --strip-components=1

SRC_DIR="$WORK_DIR/src/$THEME"
BUILD_DIR="$WORK_DIR/build/$THEME"
OUT_DIR="/usr/share/icons/$THEME"
mkdir -p "$BUILD_DIR"

for svg in "$SRC_DIR"/*.svg; do
  for size in 24 32 48 64; do
    rsvg-convert -w "$size" -h "$size" -o "$BUILD_DIR/$(basename "$svg" .svg)_${size}.png" "$svg"
  done
done

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/cursors"
for config in "$WORK_DIR"/src/config/*.cursor; do
  xcursorgen -p "$BUILD_DIR" "$config" "$OUT_DIR/cursors/$(basename "$config" .cursor)"
done
while read -r symlink target; do
  [[ -n "$symlink" && ! -e "$OUT_DIR/cursors/$symlink" ]] || continue
  ln -sf "$target" "$OUT_DIR/cursors/$symlink"
done < "$WORK_DIR/src/cursorList"
cp -f "$SRC_DIR/index.theme" "$SRC_DIR/cursor.theme" "$WORK_DIR/AUTHORS" "$WORK_DIR/LICENSE" "$OUT_DIR/"

echo "✅ Material cursors (${VARIANT}) installed: ${OUT_DIR}"
