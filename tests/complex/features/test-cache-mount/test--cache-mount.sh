#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: .booth/cache/ mount
#
# Verifies that files in .booth/cache/ are bind-mounted into the container
# at the corresponding container paths.
#
# Test 1: Individual file mount (bash_history)
# Test 2: Directory mount with .mount-this marker
# Test 3: Write inside container persists to host cache
# Test 4: A save by rename (write a new file, mv it over) persists too
# Test 5: zsh rewriting its history file (fc -W, a rename) persists
# Test 6: A path in both .booth/cache/ and .booth/shared/ refuses to start
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: .booth/cache/ mount ==="

FAILED=0

# Setup: create cache files for testing
mkdir -p .booth/cache/home/coder
echo "CACHED_BASH_HISTORY" > .booth/cache/home/coder/.bash_history

mkdir -p .booth/cache/opt/testapp
echo "" > .booth/cache/opt/testapp/.mount-this
echo "CACHED_DATA" > .booth/cache/opt/testapp/data.txt

# Ensure .gitignore contains cache/ (required by runtime validation)
if ! grep -q '^cache/' .booth/.gitignore 2>/dev/null; then
  echo "cache/" >> .booth/.gitignore
fi

# Cleanup cache on exit
cleanup() {
  rm -rf .booth/cache .booth/shared
  sed_inplace '/^cache\/$/d' .booth/.gitignore 2>/dev/null || true
}
trap cleanup EXIT

# Test 1: Individual file mount — .bash_history readable at /home/coder/.bash_history
ACTUAL=$(run_coding_booth -- cat /home/coder/.bash_history 2>/dev/null | tr -d '\r\n')
EXPECTED="CACHED_BASH_HISTORY"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" "individual file mount: .bash_history is readable"
else
  print_test_result "false" "$0" "1" "individual file mount: .bash_history should be readable"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: Directory mount with .mount-this — data.txt readable at /opt/testapp/data.txt
ACTUAL=$(run_coding_booth -- cat /opt/testapp/data.txt 2>/dev/null | tr -d '\r\n')
EXPECTED="CACHED_DATA"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "2" "directory mount: .mount-this mounts whole directory"
else
  print_test_result "false" "$0" "2" "directory mount: data.txt should be readable at /opt/testapp/"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 3: Write inside container persists to host
run_coding_booth -- 'echo WRITTEN_IN_CONTAINER > /home/coder/.bash_history' 2>/dev/null
ACTUAL=$(cat .booth/cache/home/coder/.bash_history | tr -d '\r\n')
EXPECTED="WRITTEN_IN_CONTAINER"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "3" "write inside container persists to host cache"
else
  print_test_result "false" "$0" "3" "write inside container should persist to host .booth/cache/"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 4: a single cache file is staged and copied back, so a tool that saves by
# renaming a new file over it (zsh, GLib, readline) keeps its save. A direct
# file bind mount would fail the mv with EBUSY.
run_coding_booth -- 'echo SAVED_BY_RENAME > /home/coder/.bash_history.new && mv /home/coder/.bash_history.new /home/coder/.bash_history' 2>/dev/null || true
ACTUAL=$(cat .booth/cache/home/coder/.bash_history | tr -d '\r\n')
EXPECTED="SAVED_BY_RENAME"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "4" "save by rename persists to host cache"
else
  print_test_result "false" "$0" "4" "save by rename should persist to host .booth/cache/"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 5: the real tool. zsh writes HISTFILE.new and renames it (HIST_SAVE_BY_COPY).
: > .booth/cache/home/coder/.zsh_history
run_coding_booth -- 'HISTFILE=/home/coder/.zsh_history SAVEHIST=100 HISTSIZE=100 zsh -fic "print -s ZSH_SAVED; fc -W"' 2>/dev/null || true
ACTUAL=$(tr -d '\r' < .booth/cache/home/coder/.zsh_history | grep -c '^ZSH_SAVED$' || true)
EXPECTED="1"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "5" "zsh history rewrite persists to host cache"
else
  print_test_result "false" "$0" "5" "zsh history rewrite should persist to host .booth/cache/"
  echo "  Expected: $EXPECTED line ZSH_SAVED"
  echo "  Actual:   $ACTUAL ($(cat .booth/cache/home/coder/.zsh_history))"
  FAILED=$((FAILED + 1))
fi

# Test 6: the same path from Cache and Shared is two mounts on one target. Booth
# refuses before Docker does, and names both.
mkdir -p .booth/shared/home/coder
echo "SHARED" > .booth/shared/home/coder/.bash_history
ACTUAL=$(run_coding_booth -- true 2>&1 >/dev/null || true)
rm -rf .booth/shared

if [[ "$ACTUAL" == *"both Cache and Shared"* && "$ACTUAL" == *".booth/shared/home/coder/.bash_history"* ]]; then
  print_test_result "true" "$0" "6" "a path in both cache and shared refuses to start"
else
  print_test_result "false" "$0" "6" "a path in both cache and shared should refuse to start"
  echo "  Actual stderr: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
