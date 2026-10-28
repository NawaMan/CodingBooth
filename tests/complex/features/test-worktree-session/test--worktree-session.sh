#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: `booth --worktree <name> -- cmd` leaves the repository the way it found it
#
# A worktree this run creates is removed when the booth exits, unless that
# would lose something; a worktree that already existed is never touched.
# Each step is a real one-shot booth on a scratch repository:
#
# 1) A clean run removes the worktree, its folders, and the new branch.
# 2) A run that commits removes the worktree but keeps the branch.
# 3) A run that leaves an uncommitted file keeps the worktree.
# 4) Running on that kept worktree again leaves it in place (it existed).
# 5) --keep-worktree keeps a clean worktree.
# 6) The booth is named after the branch, "/" turned into "-".
# 7) A restart (booth--restart) is not an exit: the restarted booth runs in the
#    same worktree, and only the real exit after it cleans up.
# 8) --push pushes the new commits to origin, then removes the worktree and the
#    local branch: only the pushed branch remains.
# 9) --push with uncommitted work pushes nothing, keeps the worktree, exits 1.
# 10) --push on a worktree that already existed pushes it, and leaves it.
# 11) `booth worktree list` shows a daemon booth running on its worktree.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../../../common--source.sh

if ! command -v git > /dev/null 2>&1; then
  print_test_result "true" "$0" "0" "Skipped: git not available on host"
  exit 0
fi

# The booth runs from inside the scratch repository, so resolve the build up front.
BOOTH_BIN="$(find_local_booth_build "$PWD")"

WORK="$(cd "$(mktemp -d)" && pwd -P)"
DAEMON=""
trap '[[ -n "$DAEMON" ]] && "$BOOTH_BIN" remove --name "$DAEMON" --force > /dev/null 2>&1; rm -rf "$WORK"' EXIT
git init -q -b main "$WORK/proj"
git -C "$WORK/proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
ROOT="$WORK/proj.worktrees"

booth_wt() { # args... -- the booth's command; prints the run's output, then "EXIT=<code>"
  local code=0
  (cd "$WORK/proj" && "$BOOTH_BIN" --variant base --port "$(pick_free_port)" "$@" 2>&1) || code=$?
  echo "EXIT=$code"
}
has_branch() { git -C "$WORK/proj" rev-parse --verify --quiet "refs/heads/$1" > /dev/null; }
check() { # number, description, condition result (true|false), detail
  print_test_result "$3" "$0" "$1" "$2"
  if [[ "$3" != "true" ]]; then
    echo "$4" | tail -8
    exit 1
  fi
}

OUT="$(booth_wt --worktree feature/clean -- 'echo ran')"
ok=false
[[ ! -e "$ROOT" ]] && ! has_branch feature/clean && echo "$OUT" | grep -q "^Removed worktree" && ok=true
check 1 "A clean run removes the worktree, its folders and its new branch" "$ok" "$OUT"

OUT="$(booth_wt --worktree committed -- 'git -c user.email=t@t -c user.name=t commit -q --allow-empty -m w')"
ok=false
[[ ! -e "$ROOT/committed" ]] && has_branch committed && echo "$OUT" | grep -q "^Kept branch committed" && ok=true
check 2 "A run that commits removes the worktree and keeps the branch" "$ok" "$OUT"

OUT="$(booth_wt --worktree dirty -- 'touch notes.txt')"
ok=false
[[ -f "$ROOT/dirty/notes.txt" ]] && echo "$OUT" | grep -q "^Kept worktree $ROOT/dirty: it has uncommitted changes" && ok=true
check 3 "A run with an uncommitted file keeps the worktree, and says why" "$ok" "$OUT"

OUT="$(booth_wt --worktree dirty -- 'rm notes.txt')"
ok=false
[[ -d "$ROOT/dirty" ]] && ! echo "$OUT" | grep -q "^Removed worktree" && ok=true
check 4 "A worktree that already existed is left in place, even when clean" "$ok" "$OUT"

OUT="$(booth_wt --worktree kept --keep-worktree -- 'echo ran')"
ok=false
[[ -d "$ROOT/kept" ]] && echo "$OUT" | grep -q "^Kept worktree $ROOT/kept (--keep-worktree)" && ok=true
check 5 "--keep-worktree keeps a clean worktree" "$ok" "$OUT"

OUT="$(booth_wt --worktree team/named -- 'echo "NAME=$BOOTH_CONTAINER_NAME"')"
ok=false
echo "$OUT" | grep -q "^NAME=team-named" && ok=true
check 6 "The booth is named after the branch, with / turned into -" "$ok" "$OUT"

# Run 1 commits a marker and restarts; run 2 sees the commit and exits. Had the
# restart cleaned up, run 2 would have no worktree, and the branch no commit.
RESTART_CMD='if [ "$(git log -1 --format=%s)" != restarted ]; then
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m restarted
  booth--restart --yes; sleep 60
else
  echo "RUN2 branch=$(git branch --show-current)"
fi'
OUT="$(booth_wt --worktree restarts -- "$RESTART_CMD")"
ok=false
echo "$OUT" | grep -q "^RUN2 branch=restarts" && echo "$OUT" | grep -q "^Kept branch restarts: it has 1 new commit" &&
  [[ ! -e "$ROOT/restarts" ]] && [[ "$(echo "$OUT" | grep -c '^Removed worktree')" == 1 ]] && ok=true
check 7 "A restart keeps the worktree; only the real exit after it cleans up" "$ok" "$OUT"

git init -q --bare "$WORK/origin.git"
git -C "$WORK/proj" remote add origin "$WORK/origin.git"
on_origin() { git -C "$WORK/origin.git" rev-parse --verify --quiet "refs/heads/$1"; }
COMMIT='git -c user.email=t@t -c user.name=t commit -q --allow-empty -m w'

OUT="$(booth_wt --worktree feature/pushed --push -- "$COMMIT")"
ok=false
on_origin feature/pushed > /dev/null && [[ ! -e "$ROOT/feature" ]] && ! has_branch feature/pushed &&
  echo "$OUT" | grep -q "^Pushed branch feature/pushed to origin" && echo "$OUT" | grep -q "^EXIT=0" && ok=true
check 8 "--push pushes, then removes the worktree and the local branch" "$ok" "$OUT"

OUT="$(booth_wt --worktree half --push -- "$COMMIT && touch draft.txt")"
ok=false
! on_origin half > /dev/null && [[ -f "$ROOT/half/draft.txt" ]] &&
  echo "$OUT" | grep -q "^Did not push branch half: it has uncommitted changes" && echo "$OUT" | grep -q "^EXIT=1" && ok=true
check 9 "--push with uncommitted work: not pushed, worktree kept, exit 1" "$ok" "$OUT"

OUT="$(booth_wt --worktree dirty --push -- "$COMMIT")"
ok=false
on_origin dirty > /dev/null && [[ -d "$ROOT/dirty" ]] && echo "$OUT" | grep -q "^Pushed branch dirty to origin" &&
  ! echo "$OUT" | grep -q "^Removed worktree" && ok=true
check 10 "--push on an existing worktree pushes it and leaves it in place" "$ok" "$OUT"

# An existing worktree, so --daemon needs no --keep-worktree. Name it per run: never clash.
DAEMON="wt-list-$$"
booth_wt --worktree dirty --daemon --name "$DAEMON" > /dev/null
OUT="$(cd "$WORK/proj" && "$BOOTH_BIN" worktree list 2>&1 || true)"
ok=false
echo "$OUT" | grep -qE "^dirty +$DAEMON +Running +[0-9]+ +$ROOT/dirty\$" && ok=true
check 11 "booth worktree list shows the booth running on its worktree" "$ok" "$OUT"
