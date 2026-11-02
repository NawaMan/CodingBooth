#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Installs SuperCollider: sclang (the language) and scsynth (the synthesis
# server) with the sc3-plugins UGens. scsynth is a JACK program, so live sound
# needs the host-audio+jack extension (JACK through the host's PipeWire);
# Score.recordNRT renders to a file with no audio server at all.
#
# sclang is a Qt program and aborts without a display, so /usr/local/bin/sclang
# runs it with QT_QPA_PLATFORM=offscreen when there is none (a desktop variant
# keeps its display).

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
  supercollider-language \
  supercollider-server \
  sc3-plugins-server
rm -rf /var/lib/apt/lists/*

cat > /usr/local/bin/sclang <<'EOS'
#!/bin/bash
# Written by supercollider--setup.sh: run sclang headless when there is no display.
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && -z "${QT_QPA_PLATFORM:-}" ]]; then
  export QT_QPA_PLATFORM=offscreen
fi
exec /usr/bin/sclang "$@"
EOS
chmod 755 /usr/local/bin/sclang

echo "✅ SuperCollider installed: $(dpkg-query -W -f='${Version}' supercollider-server)"
cat <<'EON'
ℹ️ Ready to use:
- sclang piece.scd                  # s.waitForBoot { ... } plays live (host-audio+jack)
- Score.recordNRT(...)              # render to a file, no audio server
EON
