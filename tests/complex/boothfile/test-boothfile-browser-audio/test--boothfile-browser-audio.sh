#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile browser-audio
#
# Verifies that the browser-audio template gives a booth its own sound server
# and that the Booth panel's stream carries what plays in it: the API server's
# /audio/state says so (and whether anything is playing), and /audio/stream answers 200 with raw PCM that holds
# the noise played through PulseAudio and through ALSA. When the viewer goes
# away, its parec goes too. check-stream.sh does the in-booth half; the nginx
# hop in front of the API server is the one every Booth panel call already uses.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile browser-audio ==="

FAILED=0
OUT=$(run_coding_booth --silence-build -- ./check-stream.sh 2>/dev/null) || OUT=""

# check NUM DESCRIPTION NAME EXPECTED-REGEX
check() {
    local value
    value=$(printf '%s\n' "$OUT" | sed -n "s/^$3: //p" | head -1)
    if [[ "$value" =~ $4 ]]; then
        print_test_result "true" "$0" "$1" "$2"
    else
        print_test_result "false" "$0" "$1" "$2"
        echo "  $3: '$value' (want /$4/)"
        FAILED=$((FAILED + 1))
    fi
}

check 1 "the booth's own sink is the default output"   "default sink" '^booth$'
check 2 "/audio/state reports the stream as running"   "state"        '"enabled":true,"running":true,"playing":false'
check 3 "/audio/stream answers 200"                    "status"       '^HTTP/1\.0 200 OK$'
# An idle sink sends nothing, so the stream holds what played: 2 s of noise,
# 384000 bytes at 48 kHz stereo s16le. At least one of those seconds must come
# through (start-up and the 3 s cut can shave the ends; under load it lands
# near 300000), and never more than the 3 s of real time the stream lasted.
bytes=$(printf '%s\n' "$OUT" | sed -n 's/^bytes: //p' | head -1)
if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes >= 192000 && bytes <= 576000 )); then
    print_test_result "true" "$0" "4" "the stream carries what played, at real time"
else
    print_test_result "false" "$0" "4" "the stream carries what played, at real time"
    echo "  bytes: '$bytes' (want 192000..576000)"
    FAILED=$((FAILED + 1))
fi
check 5 "the stream carries the sound that played"     "signal bytes" '^[1-9][0-9]{5,}$'
check 6 "parec exits when the viewer goes away"        "parec left"   '^0$'
check 7 "/audio/state says when something is playing"  "state playing" '"playing":true'

if [[ $FAILED -ne 0 ]]; then
    echo "  Full output:"
    printf '%s\n' "$OUT" | sed 's/^/    /'
fi
exit $FAILED
