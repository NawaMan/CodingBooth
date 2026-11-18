#!/bin/bash
set -euo pipefail
# Go, gopls and dlv are installed.
echo "=== Testing Go tools ==="
go version
export PATH="$(go env GOPATH)/bin:$PATH"
gopls version
dlv version
