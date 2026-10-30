#!/bin/bash
# Renders a beat and checks it is a real WAV of the expected length — needs no sound.
set -euo pipefail
echo "=== Testing beat rendering ==="
cd "$(dirname "$0")/.."
out=/tmp/test001-beat.wav
just render --bpm 120 --bars 2 --out "$out"
python3 - "$out" <<'PY'
import sys, wave
with wave.open(sys.argv[1]) as w:
    seconds = w.getnframes() / w.getframerate()
    assert w.getnchannels() == 1 and w.getframerate() == 44100, "unexpected format"
    # 2 bars at 120 BPM is 4.0 s, plus the 0.5 s tail
    assert abs(seconds - 4.5) < 0.05, f"unexpected length {seconds:.2f}s"
    print(f"OK: {seconds:.2f}s mono 44.1 kHz")
PY
