#!/bin/bash
# Test: ripgrep (apt package `ripgrep` provides the `rg` binary)

set -euo pipefail

echo "=== Testing ripgrep (rg) ==="
rg --version
echo "hello apt-example" | rg apt-example
