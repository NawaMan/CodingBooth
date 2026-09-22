#!/usr/bin/env bash
set -euo pipefail
python3 /home/coder/code/server.py >/tmp/preview-servers.log 2>&1 &
