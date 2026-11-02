#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Installs Csound, the sound-synthesis language: instruments in an orchestra,
# notes in a score, both in one .csd file. -odac plays through ALSA's default
# device, which host-audio routes to the host's speakers; -o file.wav renders
# with no audio device.

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
apt-get install -y --no-install-recommends csound
rm -rf /var/lib/apt/lists/*

echo "✅ Csound installed: $(csound --version 2>&1 | grep -m1 -i 'version')"
cat <<'EON'
ℹ️ Ready to use:
- csound -odac piece.csd            # play (host-audio)
- csound -o piece.wav piece.csd     # render to WAV
EON
