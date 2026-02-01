#!/bin/bash
# Test: imagemagick

echo "=== Testing imagemagick ==="
magick --version | head -1

TMPRED="/tmp/test-im-red-$$.png"
TMPBLUE="/tmp/test-im-blue-$$.png"

magick -size 100x100 xc:red "$TMPRED"
magick "$TMPRED" -fill blue -colorize 100% "$TMPBLUE"
echo "imagemagick created: $(file "$TMPBLUE")"
rm -f "$TMPRED" "$TMPBLUE"
