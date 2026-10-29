#!/bin/bash
set -euo pipefail
# Free Pascal and the Lazarus command-line tools are installed.
echo "=== Testing Free Pascal and Lazarus ==="
fpc -iV
command -v lazbuild
lazbuild --version
