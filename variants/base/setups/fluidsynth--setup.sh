#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Installs FluidSynth, a SoundFont synthesizer that turns MIDI into sound, with
# the small TimGM6mb General MIDI SoundFont (6 MB) as the system default
# (/usr/share/sounds/sf2/default-GM.sf2). It plays live through PulseAudio
# (host-audio) or renders a MIDI file to WAV with no audio device at all.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

# This script will always be installed by root.
HOME=/root

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends fluidsynth timgm6mb-soundfont
rm -rf /var/lib/apt/lists/*

echo "✅ FluidSynth installed: $(fluidsynth --version 2>/dev/null | grep -m1 -i 'runtime version')"
cat <<'EON'
ℹ️ Ready to use:
- fluidsynth -qni -a pulseaudio /usr/share/sounds/sf2/default-GM.sf2 song.midi   # play (host-audio)
- fluidsynth -qni -F song.wav /usr/share/sounds/sf2/default-GM.sf2 song.midi     # render to WAV
EON
