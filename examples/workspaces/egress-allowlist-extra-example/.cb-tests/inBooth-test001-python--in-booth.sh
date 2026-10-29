#!/bin/bash
set -euo pipefail
# Python is installed (the egress proxy itself needs a booth run with --egress).
echo "=== Testing Python ==="
python3 --version
python3 -c "print('ok')" | grep -q ok
