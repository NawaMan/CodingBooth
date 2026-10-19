#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile differ installation
#
# differ --version only proves a binary landed on PATH. review-in-booth.sh does
# what a user does first: open `differ review` on a repo with a change (in
# tmux, which answers the terminal queries differ waits on), check the changed
# file and line are on screen, then write a comment on a line and check differ
# saved it to .git/differ/review.json.
#
# differ--setup.sh is not on the Docker Hub base image yet. The build uses a
# locally rebuilt base, which is where that script lives.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

use_local_base_image || exit 0

echo "=== Test: Boothfile differ Installation ==="

FAILED=0

# differ opens /dev/tty unless stdin is redirected, even for --version.
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'differ --version </dev/null')
if [[ "$ACTUAL" =~ ^differ\ version\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_test_result "true" "$0" "1" "differ --version reports a release"
else
    print_test_result "false" "$0" "1" "differ --version should report a release"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'bash "$HOME/code/review-in-booth.sh"')
SCREEN="$(printf '%s\n' "$ACTUAL" | sed -n '/^=== SCREEN$/,/^=== REVIEW$/p')"
REVIEW="$(printf '%s\n' "$ACTUAL" | sed -n '/^=== REVIEW$/,$p')"

if [[ "$SCREEN" == *"main.go"* && "$SCREEN" == *'fmt.Println("hello-differ")'* ]]; then
    print_test_result "true" "$0" "2" "differ review shows the changed file and line"
else
    print_test_result "false" "$0" "2" "differ review should show main.go and the added line"
    echo "  Actual output: $(printf '%s' "$ACTUAL" | head -40)"
    FAILED=$((FAILED + 1))
fi

if [[ "$REVIEW" == *"comment-from-booth-test"* && "$REVIEW" == *"main.go"* ]]; then
    print_test_result "true" "$0" "3" "A line comment is saved to .git/differ/review.json"
else
    print_test_result "false" "$0" "3" "The comment should be saved in .git/differ/review.json"
    echo "  Actual output: $REVIEW"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
