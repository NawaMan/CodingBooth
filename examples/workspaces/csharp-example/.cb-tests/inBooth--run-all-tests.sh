#!/bin/bash
# Run all inBooth tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0

for f in "$SCRIPT_DIR"/inBooth-test*.sh; do
    [ -f "$f" ] || continue
    echo "--- $(basename "$f") ---"
    if ! bash "$f"; then
        failed=1
    fi
    echo ""
done

if [ $failed -eq 0 ]; then
    echo "All tests passed!"
else
    echo "Some tests FAILED!"
    exit 1
fi
