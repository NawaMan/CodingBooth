#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Regression: a booth opened on a git worktree must start.
#
# In a worktree (or a submodule) `.git` is a FILE holding `gitdir: <path>`, and
# that path points outside the mounted workspace -- so inside the container it
# does not resolve. Git runs repo discovery before EVERY subcommand, including
# `git config --global`, which needs no repo at all. So any unguarded git call
# from the workspace exits 128, and under `set -euo pipefail` that killed the
# entrypoint before it ever reached the user's command: no build, no
# .booth/startup.sh, not even `echo`. The booth just reported "did not become
# ready in time" with the container Exited (128).
#
# This test does not assert that git WORKS inside the booth -- the parent repo's
# .git/worktrees/<name> is still outside the mount, so it does not. It asserts
# only that a broken workspace repo cannot stop the booth from running.

set -euo pipefail

source ../common--source.sh

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
WORK_DIR=""

# `booth run` takes its code directory from the cwd, so this test has to cd into
# the worktree -- which breaks run_coding_booth's binary lookup (it searches
# upward from the script's dir). Resolve the binary first, as test008 does.
BOOTH_BIN=""
check_dir="$(pwd)"
for _ in 1 2 3 4 5; do
  if [[ -f "$check_dir/codingbooth" && -x "$check_dir/codingbooth" ]]; then
    BOOTH_BIN="$check_dir/codingbooth"
    break
  fi
  check_dir="$(dirname "$check_dir")"
done
if [[ -z "$BOOTH_BIN" ]]; then
  echo "ERROR: Could not find codingbooth" >&2
  exit 1
fi

cleanup() {
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
  return 0
}
trap cleanup EXIT

if ! command -v git > /dev/null 2>&1; then
  print_test_result "true" "$0" "0" "Skipped: git not available on host"
  exit 0
fi

# --- Build the fixture: a real worktree, not a hand-written .git file ---------
WORK_DIR="$(mktemp -d)"
git init -q "$WORK_DIR/main-repo"
git -C "$WORK_DIR/main-repo" -c user.email=test@test -c user.name=test \
    commit -q --allow-empty -m "init"
git -C "$WORK_DIR/main-repo" worktree add -q "$WORK_DIR/worktree" -b wt-test

# Sanity-check the fixture. Without this the test could pass for the wrong
# reason -- a plain clone would also print the marker.
if [[ ! -f "$WORK_DIR/worktree/.git" ]]; then
  print_test_result "false" "$0" "1" "Fixture invalid: .git is not a file (not a worktree)"
  exit 1
fi
print_test_result "true" "$0" "1" "Fixture is a git worktree (.git is a gitfile)"

# --- The regression: the booth must start and run the command ----------------
MARKER="HELLO-FROM-WORKTREE"
ACTUAL=""
cd "$WORK_DIR/worktree"
ACTUAL=$("$BOOTH_BIN" --variant base -- echo "$MARKER" 2>&1) || true

if [[ "$ACTUAL" == *"$MARKER"* ]]; then
  print_test_result "true" "$SCRIPT_PATH" "2" "Booth starts and runs a command in a git worktree"
else
  print_test_result "false" "$SCRIPT_PATH" "2" "Booth failed to run in a git worktree"
  echo "-------------------------------------------------------------------------------"
  echo "Expected output to contain: $MARKER"
  echo "-------------------------------------------------------------------------------"
  echo "Actual:"
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
