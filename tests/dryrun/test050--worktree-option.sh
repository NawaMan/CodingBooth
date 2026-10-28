#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --worktree <name> picks the code path from `git worktree list`
#
# The name matches a worktree's branch first, then its folder name, wherever
# the worktree lives. The run is then the same as --code <that path>.
#
# Test 1: from the main clone, by branch      -> mounts the worktree as code
# Test 2: same command lines as --code <path> (mounts and container name)
# Test 3: by folder name, worktree elsewhere  -> mounts that worktree
# Test 4: from inside another worktree        -> still found
# Test 5: unknown name                        -> would create it; creates nothing
# Test 6: the main clone's branch             -> error, non-zero exit
# Test 7: --worktree with --code              -> error, non-zero exit
# Test 8: --keep-worktree without --worktree  -> error, non-zero exit
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

if ! command -v git > /dev/null 2>&1; then
  print_test_result "true" "$0" "0" "Skipped: git not available on host"
  exit 0
fi

# The tests run from inside the repositories, so resolve the build up front.
BOOTH_BIN="$(find_local_booth_build "$PWD")"

WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
git init -q -b main "$WORK/main"
git -C "$WORK/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$WORK/main" worktree add -q "$WORK/main/worktree/alpha" -b alpha
git -C "$WORK/main" worktree add -q "$WORK/elsewhere/beta" -b feature/beta

FAILED=0

booth_in() { # dir, args...
    local dir="$1"; shift
    (cd "$dir" && "$BOOTH_BIN" --dryrun --variant base "$@" -- true 2>&1)
}

pass_fail() { # test-number, description, ok (true|false), detail
    print_test_result "$3" "$0" "$1" "$2"
    if [[ "$3" != "true" ]]; then
        echo "$4" | head -8
        FAILED=$((FAILED + 1))
    fi
}

code_lines() { grep -E -- 'home/coder/code|BOOTH_CONTAINER_NAME' | normalize_output; }

ACTUAL="$(booth_in "$WORK/main" --worktree alpha || true)"
ok=false; echo "$ACTUAL" | grep -qF -- "-v $WORK/main/worktree/alpha:/home/coder/code" && ok=true
pass_fail 1 "By branch, from the main clone: mounts the worktree as code" "$ok" "$ACTUAL"

EXPECT="$(booth_in "$WORK/main" --code "$WORK/main/worktree/alpha" || true)"
ok=false; diff -u <(echo "$EXPECT" | code_lines) <(echo "$ACTUAL" | code_lines) > /dev/null && ok=true
pass_fail 2 "Same mounts and container name as --code <path>" "$ok" \
    "$(diff -u <(echo "$EXPECT" | code_lines) <(echo "$ACTUAL" | code_lines) || true)"

ACTUAL="$(booth_in "$WORK/main" --worktree beta || true)"
ok=false; echo "$ACTUAL" | grep -qF -- "-v $WORK/elsewhere/beta:/home/coder/code" && ok=true
pass_fail 3 "By folder name, worktree outside the repo: found" "$ok" "$ACTUAL"

ACTUAL="$(booth_in "$WORK/elsewhere/beta" --worktree alpha || true)"
ok=false; echo "$ACTUAL" | grep -qF -- "-v $WORK/main/worktree/alpha:/home/coder/code" && ok=true
pass_fail 4 "From inside another worktree: found" "$ok" "$ACTUAL"

expect_error() { # test-number, description, message, dir, args...
    local num="$1" desc="$2" message="$3" dir="$4"; shift 4
    local out status=0
    out="$(booth_in "$dir" "$@")" || status=$?
    local ok=false
    [[ $status -ne 0 ]] && echo "$out" | grep -qF -- "$message" && ok=true
    pass_fail "$num" "$desc" "$ok" "exit=$status: $out"
}

# Worktrees live in two places here, so there is no shared root: the default applies.
ACTUAL="$(booth_in "$WORK/main" --worktree team/nope || true)"
ok=false
echo "$ACTUAL" | grep -qF "Dryrun: would create worktree $WORK/main.worktrees/team/nope on new branch team/nope" &&
    [[ ! -e "$WORK/main.worktrees" ]] && ! git -C "$WORK/main" rev-parse --verify --quiet refs/heads/team/nope > /dev/null &&
    ok=true
pass_fail 5 "Unknown name: dryrun says where it would create it, and creates nothing" "$ok" "$ACTUAL"
expect_error 6 "The main clone's branch: error" "is the main checkout" \
    "$WORK/main" --worktree main
expect_error 7 "--worktree with --code: error" "give one of them" \
    "$WORK/main" --worktree alpha --code "$WORK/main"
expect_error 8 "--keep-worktree without --worktree: error" "need --worktree" \
    "$WORK/main" --keep-worktree

exit $FAILED
