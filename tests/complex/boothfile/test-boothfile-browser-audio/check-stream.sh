#!/bin/bash
# Runs inside the booth. One "name: value" line per fact, for the test to read.
export PULSE_SERVER=${PULSE_SERVER:-unix:/run/booth-audio/native}

echo "default sink: $(pactl info 2>/dev/null | sed -n 's/^Default Sink: //p')"

request() { printf 'GET /booth-messages/api/audio/%s HTTP/1.1\r\nHost: booth\r\n\r\n' "$1"; }
echo "state: $(request state | booth-message-api-server --handle | tail -1)"

# Stream for 3 s while a second of noise plays through PulseAudio and a second
# through ALSA, which the pulse plugin routes into the same sink. Mid-noise,
# /audio/state should say something is playing.
request stream | timeout 3 booth-message-api-server --handle > /tmp/stream.http &
sleep 0.5
head -c 192000 /dev/urandom | pacat --raw --format=s16le --rate=48000 --channels=2 &
noise=$!
sleep 0.3
# In the background: the answer can take longer than the noise lasts, and the
# ALSA second must still start on time to fit inside the stream's 3 s.
request state | booth-message-api-server --handle | tail -1 > /tmp/state-playing &
wait "$noise"
aplay -q -t raw -f S16_LE -r 48000 -c 2 -d 1 /dev/urandom 2>/dev/null
wait
echo "state playing: $(cat /tmp/state-playing)"

echo "status: $(head -1 /tmp/stream.http | tr -d '\r')"
body_from=$(grep -abo $'\r\n\r\n' /tmp/stream.http | head -1 | cut -d: -f1)
tail -c +$((body_from + 5)) /tmp/stream.http > /tmp/stream.raw
echo "bytes: $(stat -c %s /tmp/stream.raw)"
echo "signal bytes: $(tr -d '\000' < /tmp/stream.raw | wc -c)"
sleep 0.5
echo "parec left: $(pgrep -c -x parec || true)"
