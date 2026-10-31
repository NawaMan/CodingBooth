#!/bin/bash
echo "=== Testing goose-lang ==="
# Checked before readlink: `readlink -f ""` resolves to the working directory,
# which would be reported as the install path.
GOOSE_LANG="$(command -v goose-lang)" \
    || { echo "goose-lang not found on PATH (the setup skips the install on non-x86_64)"; exit 1; }
# The Boothfile pins GOOSE_LANG_VERSION=2026.3: the install must be that release.
readlink -f "$GOOSE_LANG" | grep -q "/usr/local/goose-lang-2026\.3/goose$" \
    || { echo "expected goose-lang 2026.3, got: $(readlink -f "$GOOSE_LANG")"; exit 1; }
goose-lang version
