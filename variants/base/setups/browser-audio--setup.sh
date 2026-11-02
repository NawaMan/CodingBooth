#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# Plays the booth's sound in the browser tab that views it, on any host. Where
# host-audio borrows the host's sound server, this runs one in the booth:
#
#   - pulseaudio          a daemon, started as the booth user at each start,
#                         whose only output is a silent virtual sink, "booth",
#                         listening at /run/booth-audio/native (the
#                         browser-audio template points PULSE_SERVER there)
#   - booth--audio-stream records that sink's monitor with parec and answers
#                         the booth's /booth-messages/api/audio/{state,stream};
#                         the Booth panel's Sound button plays the stream
#
# The PulseAudio client side (paplay, parec, ALSA routed through PulseAudio)
# comes from host-audio--setup.sh, which the template runs first.
#
# See docs/BOOTH_AUDIO.md.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<'EOF'
Usage: browser-audio--setup.sh

  Installs an in-booth PulseAudio server with a silent "booth" sink, and the
  stream the Booth panel's Sound button plays in the browser.

Examples:
  host-audio--setup.sh && browser-audio--setup.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends pulseaudio
rm -rf /var/lib/apt/lists/*

# The socket's folder: the daemon runs as the booth user, whose UID is only
# known at start, so anyone may create it (sticky, like /tmp).
install -d -m 1777 /run/booth-audio

STREAM_BIN=/usr/local/bin/booth--audio-stream
cat >"$STREAM_BIN" <<'EOF'
#!/bin/bash
# booth--audio-stream state|http — called by booth-message-api-server.
#   state  JSON for GET /booth-messages/api/audio/state
#   http   the whole HTTP response for GET /booth-messages/api/audio/stream:
#          headers, then raw s16le 48 kHz stereo from the "booth" sink's
#          monitor until the viewer goes away (parec then dies on the write)
RATE=48000
CHANNELS=2
case "${1:-}" in
  state)
    if pactl info >/dev/null 2>&1; then running=true; else running=false; fi
    printf '{"enabled":true,"running":%s,"format":"s16le","rate":%s,"channels":%s}' \
      "$running" "$RATE" "$CHANNELS"
    ;;
  http)
    if ! pactl info >/dev/null 2>&1; then
      body='{"error":"the booth sound server is not running"}'
      printf 'HTTP/1.0 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "${#body}" "$body"
      exit 0
    fi
    # X-Accel-Buffering: nginx passes each chunk on as it comes.
    printf 'HTTP/1.0 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-store\r\nX-Accel-Buffering: no\r\nX-Audio-Format: s16le\r\nX-Audio-Rate: %s\r\nX-Audio-Channels: %s\r\nConnection: close\r\n\r\n' \
      "$RATE" "$CHANNELS"
    exec parec -d booth.monitor --raw --format=s16le --rate="$RATE" --channels="$CHANNELS" \
      --latency-msec=20 --client-name="Booth browser stream"
    ;;
  *)
    echo "Usage: booth--audio-stream state|http" >&2
    exit 2
    ;;
esac
EOF
chmod 755 "$STREAM_BIN"

STARTUP_FILE=/usr/share/startup.d/58-cb-browser-audio--startup.sh
mkdir -p "$(dirname "$STARTUP_FILE")"
cat >"$STARTUP_FILE" <<'EOF'
#!/usr/bin/env bash
# Starts the booth's own sound server: one silent sink, "booth", which the
# browser stream records. -n skips the system default.pa, so no hardware is
# probed and no other socket is opened.
export PULSE_SERVER=unix:/run/booth-audio/native
pactl info >/dev/null 2>&1 && exit 0
pulseaudio --daemonize=yes --exit-idle-time=-1 --use-pid-file=no -n \
  --load="module-native-protocol-unix socket=/run/booth-audio/native auth-anonymous=1" \
  --load="module-null-sink sink_name=booth rate=48000 sink_properties=device.description=Booth" \
  --load="module-always-sink" \
  >/tmp/booth-audio.log 2>&1 || echo "⚠️  Booth sound server did not start: see /tmp/booth-audio.log"
EOF
chmod 755 "$STARTUP_FILE"

echo "✅ Browser audio installed."
cat <<'EOF'
ℹ️ Ready to use — open the booth in the browser and click the Booth panel's Sound button, then:
  paplay sound.wav
  pactl info | grep -E '^(Server Name|Default Sink):'
EOF
