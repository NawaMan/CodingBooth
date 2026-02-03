#!/bin/bash
# Test: ffmpeg

echo "=== Testing ffmpeg ==="
ffmpeg -version | head -1

# Generate 1 second of silence, encode to mp3
TMPFILE="/tmp/test-ffmpeg-$$.mp3"
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 1 -f mp3 "$TMPFILE" -y 2>/dev/null
echo "ffmpeg created audio: $(ls -lh "$TMPFILE" | awk '{print $5}')"
rm -f "$TMPFILE"
