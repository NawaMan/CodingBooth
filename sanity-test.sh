#!/bin/bash
#
# sanity-test.sh - Basic smoke test for WorkSpace
#
# This script performs a simple sanity check by running a command inside the WorkSpace
# container and verifying that file operations work correctly. It compares output from
# the host and container to ensure basic functionality. Pass a variant name as an argument
# (default: base) to test specific WorkSpace variants.
#
set -euo pipefail

VARIANT=${1:-base}

# Define cleanup
cleanup() {
  rm -f in-workspace.txt in-host.txt
}
trap cleanup EXIT  # run cleanup on script exit (success or error)

cleanup
DATE=$(date)
echo $DATE > in-host.txt
./workspace --variant "$VARIANT" -- echo $DATE '>' in-workspace.txt

if diff -u in-workspace.txt in-host.txt; then
  echo "✅ Files match"
else
  echo "❌ Files differ"
  exit 1
fi