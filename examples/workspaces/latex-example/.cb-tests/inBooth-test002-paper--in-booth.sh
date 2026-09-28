#!/bin/bash
# Build the paper from scratch and check it came out whole: a real PDF, the
# three BibTeX entries resolved, and no undefined citations or references.
echo "=== Testing the paper builds ==="
set -e
cd "$(dirname "$0")/.."
just clean-all >/dev/null 2>&1 || true
just build >/dev/null 2>&1 || { tail -30 main.log; exit 1; }

[[ "$(head -c 5 main.pdf)" == "%PDF-" ]] || { echo "main.pdf is not a PDF"; exit 1; }
[[ "$(grep -c '\\bibitem' main.bbl)" == "3" ]] || { echo "expected 3 bibliography entries"; exit 1; }
if grep -qE "(Citation|Reference) .* undefined|There were undefined" main.log; then
    grep -E "(Citation|Reference) .* undefined|There were undefined" main.log
    exit 1
fi
just clean-all >/dev/null 2>&1 || true
echo "main.pdf built with 3 references, nothing undefined"
