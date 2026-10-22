#!/bin/bash
echo "=== Testing goose-lang ==="
# The Boothfile pins GOOSE_LANG_VERSION=2026.3: the install must be that release.
readlink -f "$(command -v goose-lang)" | grep -q "/usr/local/goose-lang-2026\.3/goose$" \
    || { echo "expected goose-lang 2026.3, got: $(readlink -f "$(command -v goose-lang)")"; exit 1; }
goose-lang version
