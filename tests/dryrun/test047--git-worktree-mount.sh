#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a booth on a git worktree also mounts the main clone's git folder
#
# A worktree's .git is a file pointing into <main>/.git/worktrees/<name>, which
# is outside the workspace mount. booth mounts <main>/.git at a neutral path,
# /opt/codingbooth/git/<repo>/.git, and covers the pointers git reads -- the
# worktree's .git file and each record's gitdir -- with generated read-only
# files that point within the booth. No host path shows in the booth. It pins
# gc.worktreePruneExpire to never so an in-booth `git gc` cannot prune the
# host's worktrees.
#
# In a booth on any repository with worktrees -- the main clone too -- each
# other worktree gets a read-only .git file under the neutral root, so an
# in-booth `git worktree prune` sees no record as stale.
#
# Test 1: worktree     -> -v <main>/.git:/opt/codingbooth/git/main/.git
# Test 2: worktree     -> GIT_CONFIG_KEY_0=gc.worktreePruneExpire
# Test 3: main clone   -> no extra git folder mount
# Test 4: main clone   -> GIT_CONFIG_KEY_0=gc.worktreePruneExpire
# Test 5: worktree     -> its .git file covered read-only
# Test 6: main clone   -> the worktree's .git under the neutral root, read-only
# Test 7: plain repo   -> no git env (no worktrees to protect)
# Test 8: worktree     -> no mount target under the host's own paths
# Test 9: worktree     -> the neutral root is a read-only tmpfs
#
# A Windows host keeps the older layout -- the host's own paths, which a
# Windows gitdir ("C:/proj/.git") cannot be -- so booth declines the mount there
# and says so, and tests 1-2 and 5-6 assert that refusal instead. The gap is
# recorded under Problems in docs/TODO.md.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

if ! command -v git > /dev/null 2>&1; then
  print_test_result "true" "$0" "0" "Skipped: git not available on host"
  exit 0
fi

WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
git init -q "$WORK/main"
git -C "$WORK/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$WORK/main" worktree add -q "$WORK/wt" -b wt
git init -q "$WORK/plain"

FAILED=0

check() { # test-number, description, expect (yes|no), pattern, code dir
    local num="$1" desc="$2" expect="$3" pattern="$4" code="$5"
    local actual found=no
    actual=$(run_coding_booth --dryrun --code "$code" --variant base -- true 2>&1 || true)
    echo "$actual" | grep -qF -- "$pattern" && found=yes
    if [[ "$found" == "$expect" ]]; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "$actual" | grep -E -- '\.git|GIT_' | head -5
        FAILED=$((FAILED + 1))
    fi
}

if [[ "$HOST_OS" == "WIN" ]]; then
    check 1 "Worktree on Windows: the mount is declined, with a reason" \
        yes "git will not work in this booth" "$WORK/wt"
    check 2 "Worktree on Windows: no half-made git mount or env" \
        no "GIT_CONFIG_KEY_0" "$WORK/wt"
    check 5 "Worktree on Windows: no .git file mirror" \
        no ".git:ro" "$WORK/wt"
    check 6 "Main clone on Windows: no .git file mirror" \
        no ".git:ro" "$WORK/main"
else
    check 1 "Worktree mounts the main clone's .git at the neutral path" \
        yes "-v $WORK/main/.git:/opt/codingbooth/git/main/.git" "$WORK/wt"
    check 2 "Worktree pins gc.worktreePruneExpire" \
        yes "GIT_CONFIG_KEY_0=gc.worktreePruneExpire" "$WORK/wt"
    check 5 "Worktree covers its own .git file read-only" \
        yes ":/home/coder/code/.git:ro" "$WORK/wt"
    check 6 "Main clone mirrors the worktree's .git file under the neutral root" \
        yes ":/opt/codingbooth/git/main/worktrees/wt/.git:ro" "$WORK/main"
    check 8 "Worktree mounts nothing at the host's own paths" \
        no ":$WORK/" "$WORK/wt"
    check 9 "Worktree's neutral root is a read-only tmpfs" \
        yes "/opt/codingbooth/git:ro,mode=755" "$WORK/wt"
fi
check 3 "Main clone gets no extra git folder mount" \
    no "$WORK/main/.git:" "$WORK/main"
check 4 "Main clone with a worktree pins gc.worktreePruneExpire" \
    yes "GIT_CONFIG_KEY_0=gc.worktreePruneExpire" "$WORK/main"
check 7 "Plain repo without worktrees gets no git env" \
    no "GIT_CONFIG_KEY_0" "$WORK/plain"

exit $FAILED
