#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Installs LilyPond, music engraving from text: a .ly file becomes a PDF score,
# and a MIDI file when the score has a \midi block. To hear that MIDI, add
# fluidsynth (the lilypond+play extension) and host-audio.

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
apt-get install -y --no-install-recommends lilypond
rm -rf /var/lib/apt/lists/*

echo "✅ LilyPond installed: $(lilypond --version | head -n1)"
cat <<'EON'
ℹ️ Ready to use:
- lilypond score.ly                 # score.pdf (+ score.midi with a \midi block)
- lilypond -o out/ score.ly         # write into out/
EON
