#!/bin/bash
# Renders every part to out/*.wav. Needs no audio device, so it works on any host.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out

echo "melody: LilyPond -> out/melody.pdf + out/melody.midi -> FluidSynth -> out/melody.wav"
lilypond -s -o out/melody score/melody.ly
fluidsynth -qni -g 0.6 -F out/melody.wav /usr/share/sounds/sf2/default-GM.sf2 out/melody.midi 2>/dev/null

echo "drums:  ChucK -> out/drums.wav"
chuck --silent drums/drums.ck:render 2>/dev/null

echo "bass:   Csound -> out/bass.wav"
csound -W -o out/bass.wav bass/bass.csd >/dev/null 2>&1

echo "pad:    SuperCollider (non-real-time) -> out/pad.wav"
sclang pad/pad.scd render >/dev/null 2>&1

ls -1 out/*.wav
