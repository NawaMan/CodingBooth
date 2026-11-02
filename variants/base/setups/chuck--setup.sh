#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Installs ChucK, the strongly-timed music language — time is a value you advance
# ("250::ms => now"), which makes drum patterns read like the beat they play.
# It plays through ALSA's default device, which host-audio routes to the host's
# speakers; --silent with a WvOut renders to a file with no audio device.

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
apt-get install -y --no-install-recommends chuck
rm -rf /var/lib/apt/lists/*

echo "✅ ChucK installed: $(chuck --version 2>&1 | grep -m1 -i 'version')"
cat <<'EON'
ℹ️ Ready to use:
- chuck drums.ck                    # play (host-audio)
- chuck --silent render.ck          # run without an audio device (record with WvOut)
EON
