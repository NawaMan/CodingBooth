#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Fresh installation
#
# fresh --version only proves a binary landed on PATH. grammar list reads the
# grammars compiled into that binary. config show reads ~/.config/fresh and
# must return the tab size just written there. The auto-selected theme startup
# writes terminal (the default theme) into that file before the editor runs.
#
# fresh--setup.sh is not on the Docker Hub base image yet. The build uses a
# locally rebuilt base, which is where that script lives.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

use_local_base_image || exit 0

echo "=== Test: Boothfile Fresh Installation ==="

FAILED=0

ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'fresh --version')
if [[ "$ACTUAL" =~ ^fresh[[:space:]][0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_test_result "true" "$0" "1" "fresh --version reports a release"
else
    print_test_result "false" "$0" "1" "fresh --version should report a release"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Dockerfile is one of the grammars compiled into the musl build.
# Match in the shell: grep -q exits at the first hit, and under pipefail that
# SIGPIPE turns a successful search of a long listing into a failed pipeline.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'fresh --no-upgrade-check --cmd grammar list')
if [[ "$ACTUAL" == *"Dockerfile"* && "$ACTUAL" == *"built-in"* ]]; then
    print_test_result "true" "$0" "2" "fresh --cmd grammar list loads built-in grammars"
else
    print_test_result "false" "$0" "2" "fresh --cmd grammar list should list the Dockerfile grammar"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# A user config must come back out of the merged config. tab_size 7 is not a
# built-in default (those are null or 8), so a hit means the file was read.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'mkdir -p "$HOME/.config/fresh" && printf "%s\n" "{\"version\":1,\"editor\":{\"tab_size\":7}}" > "$HOME/.config/fresh/config.json" && fresh --no-upgrade-check --cmd config show')
if [[ "$ACTUAL" == *'"tab_size": 7'* ]]; then
    print_test_result "true" "$0" "3" "fresh --cmd config show reads ~/.config/fresh/config.json"
else
    print_test_result "false" "$0" "3" "fresh --cmd config show should report tab_size 7"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# The startup sets theme on each start. A fresh home has no config.json, so
# this is the value a bare `fresh` selection actually opens with.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'fresh --no-upgrade-check --cmd config show')
if [[ "$ACTUAL" == *'"theme": "terminal"'* ]]; then
    print_test_result "true" "$0" "4" "fresh starts on the terminal theme"
else
    print_test_result "false" "$0" "4" "fresh should start on the terminal theme"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
