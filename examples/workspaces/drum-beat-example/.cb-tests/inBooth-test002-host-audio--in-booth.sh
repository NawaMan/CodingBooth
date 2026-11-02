#!/bin/bash
# Plays a quiet beat through the host's sound server, by PulseAudio and by ALSA.
# This proves the audio reached the host's sound server, not that anyone heard it.
#
# CB_EXPECT_HOST_AUDIO is set by the on-host test: 1 when the host has a PulseAudio
# socket to mount, so a missing socket in here is a failure; otherwise (macOS,
# Windows, a host with no sound server) the mount is skipped and so is this test.
set -euo pipefail
echo "=== Testing host audio ==="
cd "$(dirname "$0")/.."

if [[ "${CB_EXPECT_HOST_AUDIO:-0}" != "1" ]]; then
    echo "SKIP: the host has no PulseAudio socket (host-audio needs a Linux host with local Docker)"
    exit 0
fi
if [[ ! -S /run/pulse/native ]]; then
    echo "FAIL: the host has a PulseAudio socket, but /run/pulse/native is not mounted in the booth"
    exit 1
fi

just sound-check | grep -q '^Server Name:'
python3 beat.py --bars 1 --volume 0.1 --out /tmp/test002-beat.wav
paplay /tmp/test002-beat.wav
just play-alsa /tmp/test002-beat.wav
echo "OK: played through PulseAudio and ALSA"
