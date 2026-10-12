#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: git works in a booth's code folder
#
# booth cannot chown the code folder — it is a bind mount — and on an engine
# that shares the host folder through a VM (Docker Desktop, Colima, Podman
# machine) the mount ROOT arrives owned by 0:0 whoever owns it on the host,
# while everything under it maps to HOST_UID correctly. git checks the owner of
# the repository directory before every command, so every git call in the
# project answered "detected dubious ownership" and git was unusable in a booth
# on a Mac. booth-entry step 5b names the code folder in git's SYSTEM config as
# safe.directory, which is the only lever: the ownership cannot be changed (a
# chown of the mount root is silently ignored), and git reads that key only
# from protected configuration.
#
# Test 1: git runs in the code folder and reports the fixture's branch
# Test 2: the code folder is named once in the system config
# Test 3: it is system config, not coder's own — a repo cannot grant it itself
#
# Deliberately NOT `set -e`: a booth that fails to start makes every capture
# below empty, and under `set -e` the script would die on the first one having
# printed nothing to debug from. Each check reports what it got instead.
#
# Captures end in `|| true`, not the `|| OUT=""` the older tests use: with
# pipefail a booth that exits non-zero would otherwise wipe the very output
# that says why, leaving a failure whose message is "got ''".
# -------------------------------------------------------

FAILED=0

# A repo of its own, on a branch no default could coincide with: `git init`
# picks master or main depending on the host's git, and the booth's git is not
# the host's.
FIXTURE="$(mktemp -d)"
cleanup() {
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

git -c init.defaultBranch=booth-fixture init -q "$FIXTURE"
git -C "$FIXTURE" -c user.email=booth@test -c user.name=booth commit -q --allow-empty -m init

# in_booth CMD : run CMD in a booth on the fixture, all output captured.
in_booth() {
  run_coding_booth --code "$FIXTURE" --variant base --silence-build -- "$1" 2>&1
}

# -------------------------------------------------------
# Test 1: git works there, which is the whole point
# -------------------------------------------------------
OUT="$(in_booth 'git rev-parse --abbrev-ref HEAD')" || true
ACTUAL="$(printf '%s\n' "$OUT" | tail -1)"

if [[ "$ACTUAL" == "booth-fixture" ]]; then
  print_test_result "true" "$0" "1" "git runs in the booth's code folder"
else
  print_test_result "false" "$0" "1" "git should report the fixture's branch, got '$ACTUAL'"
  printf '%s\n' "${OUT:-<empty — the booth did not run>}" | tail -5 | sed 's/^/  | /'
  echo "  Hint: \"detected dubious ownership\" here means booth-entry's"
  echo "        safe.directory step did not run, or the image predates it."
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: named once — an unguarded `--add` would grow the list every start
# -------------------------------------------------------
OUT="$(in_booth 'git config --system --get-all safe.directory')" || true
ACTUAL="$(printf '%s\n' "$OUT" | grep -c '^/home/coder/code$')"

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "2" "The code folder is named once in git's system config"
else
  print_test_result "false" "$0" "2" "The code folder should be named once in git's system config, named $ACTUAL times"
  printf '%s\n' "${OUT:-<empty — the booth did not run>}" | tail -5 | sed 's/^/  | /'
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: in the system config, where a repo cannot reach
#
# git honours safe.directory only from protected configuration. Coder's own
# ~/.gitconfig is not protected for this key, and a repo that could write it
# would be granting itself the trust — so the entry must not be there.
#
# The marker is what makes "empty" mean empty: a booth that never started also
# prints nothing, and this check would pass on that silence.
# -------------------------------------------------------
OUT="$(in_booth 'printf "GLOBAL=[%s]\n" "$(git config --global --get-all safe.directory | tr "\n" " ")"')" || true
ACTUAL="$(printf '%s\n' "$OUT" | tail -1)"

if [[ "$ACTUAL" == "GLOBAL=[]" ]]; then
  print_test_result "true" "$0" "3" "The trust is system-wide, not granted in coder's own config"
else
  print_test_result "false" "$0" "3" "coder's own git config should name nothing, got '$ACTUAL'"
  printf '%s\n' "${OUT:-<empty — the booth did not run>}" | tail -5 | sed 's/^/  | /'
  FAILED=$((FAILED + 1))
fi

exit $FAILED
