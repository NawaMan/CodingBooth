#!/bin/bash
set -euo pipefail
# firefox and google-chrome are installed (no display needed)
echo "=== Testing browsers ==="
command -v firefox
firefox --version | grep -qi firefox
command -v google-chrome
google-chrome --version | grep -qi chrome
