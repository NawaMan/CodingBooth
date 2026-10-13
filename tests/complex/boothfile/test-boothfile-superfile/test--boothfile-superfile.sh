#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile superfile installation
#
# spf --version only proves a binary landed on PATH. A file manager's first
# five minutes is opening a folder, so test 3 starts the TUI on a pseudo
# terminal (script, with a set size: a 0x0 terminal draws nothing) and looks
# for the folder's entries in what it drew. The seeded config must turn update
# checks off, and must be complete: a config missing any key makes superfile
# open with a "missing fields" error instead of the files.
#
# superfile--setup.sh is not on the Docker Hub base image yet. The build uses a
# locally rebuilt base, which is where that script lives.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

use_local_base_image || exit 0

echo "=== Test: Boothfile superfile Installation ==="

FAILED=0

# spf reads stdin as a terminal unless told otherwise; </dev/null keeps the
# booth's own stdin out of it.
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'spf --version </dev/null')
if [[ "$ACTUAL" =~ ^superfile\ version\ v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_test_result "true" "$0" "1" "spf --version reports a release"
else
    print_test_result "false" "$0" "1" "spf --version should report a release"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'grep -E "^auto_check_update = " "$HOME/.config/superfile/config.toml"')
if [[ "$ACTUAL" == *"auto_check_update = false"* ]]; then
    print_test_result "true" "$0" "2" "The seeded config turns update checks off"
else
    print_test_result "false" "$0" "2" "~/.config/superfile/config.toml should set auto_check_update = false"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Two entries whose names cannot come from superfile's own chrome.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'd=$(mktemp -d) && mkdir "$d/spf-dir-marker" && touch "$d/spf-file-marker.txt" && cd "$d" && TERM=xterm-256color timeout 4 script -qfc "stty cols 120 rows 30; spf ." /tmp/spf.out </dev/null >/dev/null 2>&1; sed "s/\x1b\[[0-9;?]*[a-zA-Z]//g" /tmp/spf.out')
if [[ "$ACTUAL" == *"spf-dir-marker"* && "$ACTUAL" == *"spf-file-marker.txt"* && "$ACTUAL" != *"missing fields"* ]]; then
    print_test_result "true" "$0" "3" "spf opens a folder and lists its entries"
else
    print_test_result "false" "$0" "3" "spf should list the folder's entries with no config error"
    echo "  Actual output: $(printf '%s' "$ACTUAL" | tr -s ' ' | head -c 600)"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
