#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Installs the PulseAudio client side so code in the booth can play sound
# through the HOST's speakers. The booth runs no sound server of its own: the
# host-audio template mounts the host's PulseAudio socket (PipeWire's
# pipewire-pulse provides the same socket) read-only at /run/pulse/native and
# sets PULSE_SERVER to it. This script supplies what talks to that socket:
#
#   - pulseaudio-utils    paplay / parec / pactl (pulls in libpulse0)
#   - libasound2-plugins  ALSA's pulse plugin, made the ALSA default below, so
#                         programs that only speak ALSA (aplay, many synths)
#                         also reach the host
#   - alsa-utils          aplay / arecord, to try the ALSA route
#
# Linux hosts with local Docker only — see docs/BOOTH_AUDIO.md.

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
apt-get install -y --no-install-recommends \
  pulseaudio-utils \
  libasound2-plugins \
  alsa-utils
rm -rf /var/lib/apt/lists/*

# Route ALSA's default device to PulseAudio, which PULSE_SERVER points at the host.
cat > /etc/asound.conf <<'EOF'
# Written by host-audio--setup.sh: ALSA's default device goes through PulseAudio,
# which PULSE_SERVER points at the host's sound server.
pcm.!default { type pulse }
ctl.!default { type pulse }
EOF
chmod 644 /etc/asound.conf

echo "✅ host-audio installed:"
echo -n "   paplay: "; paplay --version 2>/dev/null | head -n1 || echo "(not found)"
echo -n "   aplay:  "; aplay --version 2>/dev/null | head -n1 || echo "(not found)"

cat <<'EON'
ℹ️ Ready to use (the booth must be started with the host-audio template's mount):
- pactl info            # shows the host's sound server and output
- paplay sound.wav      # play through the host's speakers
- aplay  sound.wav      # the same, through ALSA
EON
