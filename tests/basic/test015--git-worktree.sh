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
# Then git must WORK there: booth mounts the main clone's .git at its own path,
# so the gitfile resolves. A commit made in the booth lands in the host repo.
# And `git gc` in the booth must not prune the host's other worktrees -- their
# records hold host paths that do not exist in the container, so without the
# gc.worktreePruneExpire=never pin every old one would look stale and go.

set -euo pipefail

source ../common--source.sh

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
WORK_DIR=""

# `booth run` takes its code directory from the cwd, so this test has to cd into
# the worktree -- which breaks run_coding_booth's binary lookup (it searches
# upward from the script's dir). Resolve the binary first, as test008 does.
BOOTH_BIN="$(find_local_booth_build)" || {
  echo "ERROR: Could not find codingbooth" >&2
  exit 1
}

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

# --- git works in the booth ----------------------------------------------------
# A second worktree, old enough that an unguarded `git gc` would prune it.
git -C "$WORK_DIR/main-repo" worktree add -q "$WORK_DIR/other" -b other
# git judges staleness by the record's index mtime, so backdate the whole record.
touch_year_ago "$WORK_DIR/main-repo/.git/worktrees/other/"*

ACTUAL=$("$BOOTH_BIN" --variant base -- bash -c '
  echo "BRANCH=$(git rev-parse --abbrev-ref HEAD)"
  git -c user.email=b@b -c user.name=booth commit -q --allow-empty -m from-booth && echo COMMITTED
  git gc -q && echo GC-DONE
' 2>&1) || true

# Tests 3-5 need the .git mirror, which only works where the host's own
# absolute path is also a path a container can hold. A Windows gitdir
# ("C:/proj/.git") is not, so booth declines the mount and says so (same
# limitation as dryrun/test047; recorded under Problems in docs/TODO.md). What
# holds there is the regression this file opens with: the booth still starts and
# still runs the command, with a warning instead of a broken mount.
if [[ "$HOST_OS" == "WIN" ]]; then
  if [[ "$ACTUAL" == *"git will not work in this booth"* ]]; then
    print_test_result "true" "$SCRIPT_PATH" "3" "the booth starts and says why git will not work (no .git mirror on this host)"
  else
    print_test_result "false" "$SCRIPT_PATH" "3" "the booth should warn that git will not work on this host"
    echo "$ACTUAL"
    exit 1
  fi
  exit 0
fi

if [[ "$ACTUAL" == *"BRANCH=wt-test"* ]]; then
  print_test_result "true" "$SCRIPT_PATH" "3" "git finds the worktree's repo in the booth"
else
  print_test_result "false" "$SCRIPT_PATH" "3" "git cannot find the worktree's repo in the booth"
  echo "$ACTUAL"
  exit 1
fi

if [[ "$ACTUAL" == *COMMITTED* ]] &&
   [[ "$(git -C "$WORK_DIR/main-repo" log -1 --format=%s wt-test)" == "from-booth" ]]; then
  print_test_result "true" "$SCRIPT_PATH" "4" "A commit made in the booth lands in the host repo"
else
  print_test_result "false" "$SCRIPT_PATH" "4" "A commit made in the booth did not land in the host repo"
  echo "$ACTUAL"
  exit 1
fi

if [[ "$ACTUAL" == *GC-DONE* ]] && [[ -d "$WORK_DIR/main-repo/.git/worktrees/other" ]] &&
   git -C "$WORK_DIR/other" status > /dev/null 2>&1; then
  print_test_result "true" "$SCRIPT_PATH" "5" "git gc in the booth leaves the host's other worktrees"
else
  print_test_result "false" "$SCRIPT_PATH" "5" "git gc in the booth pruned the host's other worktree"
  echo "$ACTUAL"
  exit 1
fi

# --- The host's paths stay out of the booth ------------------------------------
# booth shows git a neutral layout (/opt/codingbooth/git/<repo>/.git) instead of
# mounting the main clone's .git at its host path, so the host's folders -- which
# look like the user's home and, made by the engine, are writable with sudo --
# never appear. The neutral root is a read-only tmpfs, so even root cannot write
# there. And with the records covered, an in-booth `git worktree prune` sees no
# live worktree as stale.
ACTUAL=$("$BOOTH_BIN" --variant base -- bash -c '
  if [ -e "'"$WORK_DIR"'" ]; then echo HOST-PATH-VISIBLE; else echo HOST-PATH-ABSENT; fi
  if sudo -n touch /opt/codingbooth/git/probe 2>/dev/null; then echo NEUTRAL-WRITABLE; else echo NEUTRAL-READ-ONLY; fi
  git worktree prune -v 2>&1 && echo PRUNE-DONE
' 2>&1) || true

if [[ "$ACTUAL" == *HOST-PATH-ABSENT* && "$ACTUAL" == *NEUTRAL-READ-ONLY* ]]; then
  print_test_result "true" "$SCRIPT_PATH" "6" "The host's paths are absent from the booth, and the neutral root is read-only"
else
  print_test_result "false" "$SCRIPT_PATH" "6" "The host's paths show in the booth, or the neutral root is writable"
  echo "$ACTUAL"
  exit 1
fi

if [[ "$ACTUAL" == *PRUNE-DONE* && "$ACTUAL" != *Removing* ]] &&
   [[ -d "$WORK_DIR/main-repo/.git/worktrees/other" ]]; then
  print_test_result "true" "$SCRIPT_PATH" "7" "git worktree prune in the booth drops no live worktree"
else
  print_test_result "false" "$SCRIPT_PATH" "7" "git worktree prune in the booth dropped a live worktree"
  echo "$ACTUAL"
  exit 1
fi

# --- A worktree added in the booth works on the host after the next start -------
# git in the booth writes the new worktree's .git file and record with the paths
# it sees there. The next booth on the same folder writes the host's back.
ACTUAL=$("$BOOTH_BIN" --variant base -- bash -c '
  git worktree add -q in/added -b added && echo ADDED
' 2>&1) || true
"$BOOTH_BIN" --variant base -- true > /dev/null 2>&1 || true
ADDED_GIT="$WORK_DIR/worktree/in/added/.git"
RECORD="$WORK_DIR/main-repo/.git/worktrees/added/gitdir"
if [[ "$ACTUAL" == *ADDED* ]] &&
   git -C "$WORK_DIR/worktree/in/added" status > /dev/null 2>&1 &&
   [[ "$(cat "$RECORD" 2>/dev/null)" == "$ADDED_GIT" ]]; then
  print_test_result "true" "$SCRIPT_PATH" "8" "A worktree added in the booth works on the host after the next booth start"
else
  print_test_result "false" "$SCRIPT_PATH" "8" "A worktree added in the booth is still broken on the host"
  echo "$ACTUAL"
  echo "record: $(cat "$RECORD" 2>&1)"
  echo ".git:   $(cat "$ADDED_GIT" 2>&1)"
  exit 1
fi

# --- With its own .booth/, the pointers live there, read-only in the booth -------
# A workspace that has a .booth/ keeps git's pointer files in .booth/.tmp/git-pointers/,
# so they go with the folder. That folder is inside the writable workspace mount, so booth
# covers it read-only: an edit in place would change what git reads.
mkdir -p "$WORK_DIR/worktree/.booth"
ACTUAL=$("$BOOTH_BIN" --variant base -- bash -c '
  echo "BRANCH=$(git rev-parse --abbrev-ref HEAD)"
  f=$(ls /home/coder/code/.booth/.tmp/git-pointers/* | head -1)
  if [ -n "$f" ] && ! sudo -n sh -c "echo x > $f" 2>/dev/null; then echo POINTERS-READ-ONLY; else echo POINTERS-WRITABLE; fi
' 2>&1) || true
POINTERS="$WORK_DIR/worktree/.booth/.tmp/git-pointers"
if [[ "$ACTUAL" == *"BRANCH=wt-test"* && "$ACTUAL" == *POINTERS-READ-ONLY* ]] &&
   [[ -n "$(ls -A "$POINTERS" 2>/dev/null)" ]]; then
  print_test_result "true" "$SCRIPT_PATH" "9" "With .booth/, the pointers are kept in .booth/.tmp/git-pointers/ (read-only in the booth, kept after exit)"
else
  print_test_result "false" "$SCRIPT_PATH" "9" "With .booth/, the pointers are not in .booth/.tmp/git-pointers/, or are writable in the booth"
  echo "$ACTUAL"
  echo "on the host: $(ls -A "$POINTERS" 2>&1)"
  exit 1
fi
