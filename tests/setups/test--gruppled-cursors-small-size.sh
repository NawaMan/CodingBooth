#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: gruppled-cursors--setup.sh adds 24px and 30px cursor sizes
#
# Gruppled ships only a ~40px image per cursor and Xcursor never scales, so the
# setup shrinks that image into extra 24px and 30px ones, for a smaller cursor
# than the booth's default 40.
# This runs the real script against a synthetic theme tarball (curl stubbed)
# and reads the Xcursor files back:
#   - every cursor gains a 24px and a 30px image, the 40px one is kept
#   - every frame of an animated cursor is shrunk, delays kept, order kept
#   - the hotspot scales with the image
#   - a symlinked cursor is not processed twice; an empty file is left alone
#   - a file that already has 24px and 30px is left byte-identical
#
# /usr/share/icons is redirected into a temp dir by cp/rm/ls stubs, so nothing
# outside the temp dir is touched.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/gruppled-cursors--setup.sh"

if ! have_python3; then
    echo "SKIP: no working python3 (the setup's resize step needs it)"
    exit 0
fi

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/src" "$STUB/icons"
ICONS="$STUB/icons"

# ---- a synthetic Gruppled tarball ------------------------------------------
CURSORS="$STUB/src/gruppled-cursors-test/gruppled_white/cursors"
mkdir -p "$CURSORS"
python3 - "$CURSORS" <<'PY'
import os, struct, sys
IMAGE, COMMENT = 0xfffd0002, 0xfffe0001
def image(size, w, h, xhot, yhot, delay, argb):
    return (IMAGE, size, struct.pack('<9I', 36, IMAGE, size, 1, w, h, xhot, yhot, delay)
            + struct.pack(f'<{w*h}I', *([argb] * (w * h))))
def comment(text):
    b = text.encode()
    return (COMMENT, 1, struct.pack('<5I', 20, COMMENT, 1, 1, len(b)) + b)
def write(path, chunks):
    toc, body, pos = b'', b'', 16 + 12 * len(chunks)
    for kind, sub, c in chunks:
        toc += struct.pack('<III', kind, sub, pos + len(body)); body += c
    open(path, 'wb').write(b'Xcur' + struct.pack('<III', 16, 0x10000, len(chunks)) + toc + body)
d = sys.argv[1]
write(f'{d}/left_ptr', [comment('Gruppled'), image(40, 40, 40, 10, 5, 50, 0xff336699)])
write(f'{d}/watch', [image(39, 40, 40, 20, 20, dl, 0x80402010) for dl in (10, 20, 30)])
write(f'{d}/already', [image(24, 24, 24, 1, 1, 0, 0xffffffff), image(30, 30, 30, 1, 1, 0, 0xffffffff),
                       image(48, 48, 48, 2, 2, 0, 0xffffffff)])
open(f'{d}/empty', 'wb').close()
os.symlink('left_ptr', f'{d}/arrow')
PY
cp -p "$CURSORS/already" "$STUB/already.orig"
tar -czf "$STUB/gruppled.tar.gz" -C "$STUB/src" gruppled-cursors-test

# ---- stubs -----------------------------------------------------------------
LOG="$STUB/calls.log"
: > "$LOG"
cat > "$STUB/bin/apt--install.sh" <<EOF
#!/bin/bash
echo "apt--install.sh \$*" >> "$LOG"
EOF
cat > "$STUB/bin/curl" <<EOF
#!/bin/bash
cat "$STUB/gruppled.tar.gz"
EOF
# cp, rm and ls see /usr/share/icons as the temp icons dir; everything else is real.
# The script's `ls -d /usr/share/icons/gruppled_*` reaches the stub unexpanded (no
# match on the host), so a redirected argument holding a * is globbed again here.
for tool in cp rm ls; do
    real="$(command -v "$tool")"
    cat > "$STUB/bin/$tool" <<EOF
#!/bin/bash
args=()
for a in "\$@"; do
  b="\${a/#\/usr\/share\/icons/$ICONS}"
  if [[ "\$b" != "\$a" && "\$b" == *'*'* ]]; then args+=(\$b); else args+=("\$b"); fi
done
exec "$real" "\${args[@]}"
EOF
done
chmod +x "$STUB/bin/"*

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        ALL_PASSED=false
    fi
}

# Prints one line per image chunk: "<nominal> <w>x<h> hot=<x>,<y> delay=<d> px=<first pixel>",
# then "comments=<n>". "not-xcursor" for anything else.
describe() {
    python3 - "$1" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
if d[:4] != b'Xcur':
    print('not-xcursor'); sys.exit()
h, _, n = struct.unpack_from('<III', d, 4)
comments = 0
for i in range(n):
    kind, sub, pos = struct.unpack_from('<III', d, h + 12 * i)
    if kind == 0xfffd0002:
        _, _, _, _, w, hh, x, y, dl = struct.unpack_from('<9I', d, pos)
        print(f'{sub} {w}x{hh} hot={x},{y} delay={dl} px={struct.unpack_from("<I", d, pos + 36)[0]:08x}')
    elif kind == 0xfffe0001:
        comments += 1
print(f'comments={comments}')
PY
}

# ---- run the real script ---------------------------------------------------
RUN_EXIT=0
RUN_OUT=$(PATH="$STUB/bin:$PATH" /usr/bin/env EUID=0 bash "$SCRIPT" white 2>&1) || RUN_EXIT=$?

check "exits 0" "$([[ $RUN_EXIT -eq 0 ]] && echo true || { echo "$RUN_OUT" | sed 's/^/      /' >&2; echo false; })"
check "installs python3-minimal for the resize step" \
      "$(grep -q "apt--install.sh .*python3-minimal" "$LOG" && echo true || echo false)"

OUT="$ICONS/gruppled_white/cursors"
LEFT=$(describe "$OUT/left_ptr")
WATCH=$(describe "$OUT/watch")

check "left_ptr keeps its 40px image" \
      "$(grep -qx "40 40x40 hot=10,5 delay=50 px=ff336699" <<<"$LEFT" && echo true || echo false)"
check "left_ptr gains a 24x24 image, hotspot scaled to 6,3, colour kept" \
      "$(grep -qx "24 24x24 hot=6,3 delay=50 px=ff336699" <<<"$LEFT" && echo true || echo false)"
check "left_ptr is resized once, though 'arrow' links to it" \
      "$(echo "$LEFT" | grep -c "^24 " | grep -qx 1 && echo true || echo false)"
check "left_ptr gains a 30x30 image, hotspot scaled to 8,4, colour kept" \
      "$(grep -qx "30 30x30 hot=8,4 delay=50 px=ff336699" <<<"$LEFT" && echo true || echo false)"
check "left_ptr gets its 30px image once, though 'arrow' links to it" \
      "$(echo "$LEFT" | grep -c "^30 " | grep -qx 1 && echo true || echo false)"
check "left_ptr keeps its comment chunk" \
      "$(grep -qx "comments=1" <<<"$LEFT" && echo true || echo false)"

# watch: nominal 39, 40x40 images -> 24/39 scale = 25x25; three frames, in order.
check "every watch frame gains a small image, delays in order" \
      "$([[ "$(grep "^24 " <<<"$WATCH" | sed 's/.*delay=\([0-9]*\).*/\1/' | tr '\n' ' ')" == "10 20 30 " ]] && echo true || echo false)"
# and 30/39 scale = 31x31, again three frames in order.
check "every watch frame gains a 30px image, delays in order" \
      "$([[ "$(grep "^30 31x31 " <<<"$WATCH" | sed 's/.*delay=\([0-9]*\).*/\1/' | tr '\n' ' ')" == "10 20 30 " ]] && echo true || echo false)"
check "watch keeps its three 39px frames" \
      "$([[ "$(grep -c "^39 " <<<"$WATCH")" == 3 ]] && echo true || echo false)"
check "a semi-transparent frame keeps its premultiplied colour" \
      "$(grep -q "^24 25x25 hot=12,12 delay=10 px=80402010$" <<<"$WATCH" && echo true || echo false)"

check "an empty file is left empty" "$([[ -f "$OUT/empty" && ! -s "$OUT/empty" ]] && echo true || echo false)"
check "a cursor that already has 24px and 30px is left byte-identical" \
      "$(cmp -s "$OUT/already" "$STUB/already.orig" && echo true || echo false)"

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "--- left_ptr"; echo "$LEFT"; echo "--- watch"; echo "$WATCH"
    exit 1
fi
