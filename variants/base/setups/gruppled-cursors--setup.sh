#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.3.0

# gruppled-cursors--setup.sh — Gruppled Cursors by Craig Laparo (https://www.xfce-look.org/p/999974),
# prebuilt White and Black variants installed system-wide. It does not change the
# default cursor (xfce-theme--setup.sh does); pick it in Settings → Mouse and
# Touchpad → Theme, or `booth--theme set cursor gruppled_white`.
#
# The pling download link is a signed, expiring URL, so this fetches the GitHub
# re-upload instead (verified byte-identical to the pling tarball). The cursors
# only carry a 40px image, and Xcursor never scales: at another size it uses the
# nearest image a file has. So 24px and 30px images, shrunk from the 40px one,
# are added to every cursor here. Gruppled draws a small arrow on its canvas:
# at 30 it is about 14x22, the size of Adwaita's at 24, so 30 is the booth
# default (xfce-theme--setup.sh); 24 and 40 are there for
# `booth--theme set cursor-size 24` / `40`.
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
SMALL_SIZES=(24 30)

apt--install.sh curl ca-certificates python3-minimal

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "https://github.com/nim65s/gruppled-cursors/archive/${GRUPPLED_REF}.tar.gz" \
  | tar -xz -C "$WORK_DIR" --strip-components=1

# add_cursor_size DIR SIZE — add a SIZE image, shrunk from the largest one, to
# every Xcursor file in DIR (symlinks share their target's file). Every frame of
# an animated cursor is shrunk, and the hotspot moves with the scale.
add_cursor_size() {
  python3 - "$1" "$2" <<'PY'
import math, os, struct, sys

IMAGE, COMMENT = 0xfffd0002, 0xfffe0001
cursor_dir, target = sys.argv[1], int(sys.argv[2])

def chunk_size(data, pos, kind):
    if kind == IMAGE:
        width, height = struct.unpack_from('<II', data, pos + 16)
        return 36 + 4 * width * height
    if kind == COMMENT:
        return 20 + struct.unpack_from('<I', data, pos + 16)[0]
    raise ValueError(f'unknown Xcursor chunk type {kind:#x}')

# Area average. Xcursor pixels are premultiplied ARGB, so channels average as-is.
def shrink(pixels, width, height, new_width, new_height):
    scale_x, scale_y = width / new_width, height / new_height
    out = []
    for dy in range(new_height):
        y0, y1 = dy * scale_y, (dy + 1) * scale_y
        for dx in range(new_width):
            x0, x1 = dx * scale_x, (dx + 1) * scale_x
            sums, area = [0.0, 0.0, 0.0, 0.0], 0.0
            for y in range(int(y0), min(height, math.ceil(y1))):
                wy = min(y1, y + 1) - max(y0, y)
                for x in range(int(x0), min(width, math.ceil(x1))):
                    w = wy * (min(x1, x + 1) - max(x0, x))
                    p = pixels[y * width + x]
                    for i, shift in enumerate((24, 16, 8, 0)):
                        sums[i] += w * ((p >> shift) & 0xff)
                    area += w
            a, r, g, b = (min(255, round(s / area)) for s in sums)
            out.append(a << 24 | r << 16 | g << 8 | b)
    return out

count = 0
for name in sorted(os.listdir(cursor_dir)):
    path = os.path.join(cursor_dir, name)
    if os.path.islink(path) or not os.path.isfile(path):
        continue
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'Xcur':
        continue
    header, version, ntoc = struct.unpack_from('<III', data, 4)
    toc = [struct.unpack_from('<III', data, header + 12 * i) for i in range(ntoc)]
    sizes = {size for kind, size, _ in toc if kind == IMAGE}
    if not sizes or target in sizes:
        continue
    source = max(sizes)
    chunks = [(kind, size, data[pos:pos + chunk_size(data, pos, kind)]) for kind, size, pos in toc]
    for kind, size, chunk in list(chunks):
        if kind != IMAGE or size != source:
            continue
        _, _, _, _, width, height, xhot, yhot, delay = struct.unpack_from('<9I', chunk)
        new_width = max(1, round(width * target / source))
        new_height = max(1, round(height * target / source))
        pixels = struct.unpack_from(f'<{width * height}I', chunk, 36)
        small = shrink(pixels, width, height, new_width, new_height)
        new_xhot = min(new_width - 1, round(xhot * new_width / width))
        new_yhot = min(new_height - 1, round(yhot * new_height / height))
        chunks.append((IMAGE, target,
                       struct.pack('<9I', 36, IMAGE, target, 1, new_width, new_height,
                                   new_xhot, new_yhot, delay)
                       + struct.pack(f'<{len(small)}I', *small)))
    toc_out, body, pos = b'', b'', 16 + 12 * len(chunks)
    for kind, size, chunk in chunks:
        toc_out += struct.pack('<III', kind, size, pos + len(body))
        body += chunk
    with open(path, 'wb') as f:
        f.write(b'Xcur' + struct.pack('<III', 16, version, len(chunks)) + toc_out + body)
    count += 1
print(f'• Added a {target}px size to {count} cursors in {cursor_dir}')
PY
}

for variant in ${VARIANTS//,/ }; do
  theme="gruppled_${variant}"
  if [[ ! -d "$WORK_DIR/$theme/cursors" ]]; then
    echo "❌ Unknown variant '$variant' (white|black)" >&2
    exit 1
  fi
  for size in "${SMALL_SIZES[@]}"; do
    add_cursor_size "$WORK_DIR/$theme/cursors" "$size"
  done
  rm -rf "/usr/share/icons/$theme"
  cp -r "$WORK_DIR/$theme" "/usr/share/icons/$theme"
done

echo "✅ Gruppled cursors (${VARIANTS}) installed:"
ls -d /usr/share/icons/gruppled_*
