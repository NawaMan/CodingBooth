#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: glow ships in the base image
#
# glow is installed by variants/base/setups/glow--setup.sh from the
# Dockerfile, so every variant inherits it.
#
# Deliberately NOT `set -e`, for the reason test022--lazygit.sh gives: a booth
# that fails to start would otherwise end the script with no output at all.
# -------------------------------------------------------

FAILED=0

# Test 1: glow is on PATH
ACTUAL=$(run_coding_booth --variant base -- 'command -v glow' 2>&1 | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "/usr/local/bin/glow" ]]; then
  print_test_result "true" "$0" "1" "glow is installed in the base image"
else
  print_test_result "false" "$0" "1" "glow is installed in the base image"
  echo "  Got: ${ACTUAL:-<empty — the booth did not run>} (want /usr/local/bin/glow)"
  echo "  Hint: an image built before glow joined the base lacks it; rebuild with"
  echo "        ./build/docker-build.sh base"
  FAILED=$((FAILED + 1))
fi

# Test 2: glow reports the pinned version
ACTUAL=$(run_coding_booth --variant base -- 'glow --version' 2>&1 | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == *"glow version 3.0.0"* ]]; then
  print_test_result "true" "$0" "2" "glow reports the pinned version ($ACTUAL)"
else
  print_test_result "false" "$0" "2" "glow reports the pinned version"
  echo "  Got: ${ACTUAL:-<empty — the booth did not run>} (want 'glow version 3.0.0')"
  FAILED=$((FAILED + 1))
fi

# Test 3: glow actually renders Markdown
#
# --version proves the file runs; this proves it is glow. -s notty is the plain
# style for a non-terminal, so the heading text comes out without escapes.
# The </dev/null matters: glow renders a piped stdin in preference to the file
# it is given, and `booth -- cmd` hands the command a pipe, so without it glow
# renders an empty document and exits 0.
ACTUAL=$(run_coding_booth --variant base -- \
  'printf "# Hello Glow\n\nsome *text*\n" > /tmp/g.md && glow -s notty /tmp/g.md </dev/null | grep -c "Hello Glow"' \
  2>&1 | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "3" "glow renders a Markdown file"
else
  print_test_result "false" "$0" "3" "glow renders a Markdown file"
  echo "  Matching lines: ${ACTUAL:-<empty — the booth did not run>} (want 1)"
  FAILED=$((FAILED + 1))
fi

# Test 4: the man page and completions came with it
ACTUAL=$(run_coding_booth --variant base -- \
  'ls /usr/local/share/man/man1/glow.1.gz /usr/share/bash-completion/completions/glow /usr/local/share/zsh/site-functions/_glow /usr/share/fish/vendor_completions.d/glow.fish 2>/dev/null | wc -l' \
  2>&1 | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "4" ]]; then
  print_test_result "true" "$0" "4" "glow's man page and shell completions are installed"
else
  print_test_result "false" "$0" "4" "glow's man page and shell completions are installed"
  echo "  Files found: ${ACTUAL:-<empty — the booth did not run>} (want 4)"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
