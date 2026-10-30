#!/bin/bash
# Renders every part and checks each tool made real output — needs no sound,
# so it runs on any host.
set -euo pipefail
echo "=== Testing render: LilyPond, FluidSynth, ChucK, Csound, SuperCollider ==="
cd "$(dirname "$0")/.."
rm -rf out
just render

test -s out/melody.pdf  || { echo "FAIL: LilyPond wrote no PDF";  exit 1; }
test -s out/melody.midi || { echo "FAIL: LilyPond wrote no MIDI"; exit 1; }
echo "OK: out/melody.pdf and out/melody.midi"

# le32 FILE OFFSET — a little-endian 32-bit field of a WAV header.
le32() { od -An -tu4 -j "$2" -N 4 --endian=little "$1" | tr -d ' '; }

# Every part is 4 bars at 120 BPM (8 s) plus a short tail, and must not be silence.
for part in melody drums bass pad; do
    f="out/$part.wav"
    test -s "$f" || { echo "FAIL: no $f"; exit 1; }
    byte_rate=$(le32 "$f" 28)
    tenths=$(( ($(stat -c %s "$f") - 44) * 10 / byte_rate ))
    nonzero=$(tail -c +45 "$f" | tr -d '\000' | wc -c)
    if (( tenths < 75 || tenths > 120 )); then
        echo "FAIL: $f is $((tenths / 10)).$((tenths % 10)) s, expected about 8.5 s"; exit 1
    fi
    if (( nonzero < 10000 )); then
        echo "FAIL: $f is silent ($nonzero non-zero bytes)"; exit 1
    fi
    echo "OK: $f $((tenths / 10)).$((tenths % 10)) s, not silent"
done
