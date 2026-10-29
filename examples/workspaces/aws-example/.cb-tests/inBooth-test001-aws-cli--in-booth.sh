#!/bin/bash
set -euo pipefail
# aws CLI and claude binaries run (no credentials used)
echo "=== Testing aws-cli ==="
aws --version
echo "=== Testing claude ==="
claude --version
