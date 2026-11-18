#!/bin/bash
# Renders all four parts, then plays them together on the host's speakers.
# Rendering first keeps them in time: live, SuperCollider's server boot alone
# would put the pad a second behind the drums.
set -euo pipefail
cd "$(dirname "$0")"
./render.sh
echo "jam: playing melody + drums + bass + pad"
for part in melody drums bass pad; do
    paplay "out/$part.wav" &
done
wait
