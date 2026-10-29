#!/bin/bash
set -euo pipefail
# octave is installed and evaluates an expression
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing octave ==="
octave-cli --version | grep -qi octave
octave-cli --eval "disp(1+2)" | grep -q 3
