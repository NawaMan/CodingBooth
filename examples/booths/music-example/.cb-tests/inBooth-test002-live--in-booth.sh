#!/bin/bash
# Plays each tool live, quietly enough, through the host's sound server:
# ChucK and Csound through ALSA -> PulseAudio, FluidSynth through PulseAudio,
# SuperCollider through JACK -> PipeWire. This proves the sound reached the
# host's sound server, not that anyone heard it.
#
# CB_EXPECT_HOST_AUDIO is set by the on-host test: 1 when the host has the
# PulseAudio and PipeWire sockets to mount, so a missing one in here is a
# failure; otherwise (macOS, Windows, a host with no PipeWire) this test skips.
set -euo pipefail
echo "=== Testing live playback ==="
cd "$(dirname "$0")/.."

if [[ "${CB_EXPECT_HOST_AUDIO:-0}" != "1" ]]; then
    echo "SKIP: the host has no PulseAudio + PipeWire sockets (needs a Linux host with PipeWire and local Docker)"
    exit 0
fi
for sock in /run/pulse/native /run/pipewire/pipewire-0; do
    [[ -S "$sock" ]] || { echo "FAIL: the host has the socket, but $sock is not mounted in the booth"; exit 1; }
done

just sound-check | grep -q '^Server Name:'
timeout 60  just drums
timeout 60  just bass
timeout 120 just melody
out=$(timeout 90 just pad 2>&1)
echo "$out" | grep -q 'JackDriver: connected' || { echo "$out" | tail -20; echo "FAIL: SuperCollider did not reach JACK"; exit 1; }
echo "OK: ChucK, Csound, FluidSynth and SuperCollider played live"
