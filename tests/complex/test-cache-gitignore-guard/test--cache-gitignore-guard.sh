#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: .booth/cache/ gitignore guard
#
# The cache is whatever the container writes to the mounted paths, and that can
# include live credentials: with claude-code+settings-cache, ~/.claude/ is a
# whole-directory bind mount, so the host token copied to
# ~/.claude/.credentials.json lands inside the project tree. The booth therefore
# refuses to start unless .booth/cache/ is out of git's reach.
#
# Test 1: Cache not gitignored             -> refuses to start
# Test 2: Cache TRACKED despite a cache/ rule -> refuses to start
#         (a gitignore rule does not apply to files git already tracks; this is
#          the case a grep of .booth/.gitignore reports as fine)
# Test 3: After untracking                 -> starts, and the cache is mounted
# Test 4: Not a git repo                   -> guard skipped, starts
# Test 5: Cache over a protected path      -> refuses to start
#
# The projects are created outside the repo: this repo gitignores **/.booth/cache/,
# so a cache dir inside it can never be un-ignored, and the failure cases could
# not be reproduced here.
#
# Uses --dryrun throughout — the guard runs while the docker args are built, so
# no container is needed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: .booth/cache/ gitignore guard ==="

FAILED=0

# The guard has to be exercised from inside a foreign project directory, so the usual
# run_coding_booth helper does not fit: it locates the binary relative to the caller's
# cwd, which we change. Resolve it once here instead. (SCRIPT_DIR is tests/complex/<test>.)
BOOTH_BIN="$(cd "$SCRIPT_DIR/../../.." && pwd)/codingbooth"
if [[ ! -x "$BOOTH_BIN" ]]; then
  echo "ERROR: codingbooth not found at $BOOTH_BIN — build it first" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# new_project <name> [--no-git] — a project with a credential sitting in the cache.
new_project() {
  local proj="$WORK_DIR/$1"
  mkdir -p "$proj/.booth/cache/home/coder/.claude"
  printf 'variant = "base"\n' > "$proj/.booth/config.toml"
  printf '{"accessToken":"SECRET-TOKEN"}' > "$proj/.booth/cache/home/coder/.claude/.credentials.json"
  printf '' > "$proj/.booth/cache/home/coder/.claude/.mount-this"

  if [[ "${2:-}" != "--no-git" ]]; then
    git -C "$proj" init -q
    git -C "$proj" config user.email "test@example.com"
    git -C "$proj" config user.name  "Test"
  fi
  echo "$proj"
}

# run_guard <project dir> — start a booth in that project, capturing output and exit code
# without tripping set -e. --dryrun is enough: the guard runs while the docker args are
# built, so it fires before any container would start.
GUARD_OUT=""
GUARD_RC=0
run_guard() {
  set +e
  GUARD_OUT=$(cd "$1" && "$BOOTH_BIN" --dryrun -- true 2>&1)
  GUARD_RC=$?
  set -e
}

check() { # <ok> <n> <description>
  if [[ "$1" == "true" ]]; then
    print_test_result "true" "$0" "$2" "$3"
  else
    print_test_result "false" "$0" "$2" "$3"
    echo "  Exit code: $GUARD_RC"
    echo "  Output:    $GUARD_OUT"
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: a cache with no gitignore rule anywhere must not start.
PROJ_1="$(new_project not-ignored)"
run_guard "$PROJ_1"
if [[ "$GUARD_RC" -ne 0 ]] && grep -q "NOT gitignored" <<< "$GUARD_OUT"; then
  check true 1 "cache not gitignored: refuses to start"
else
  check false 1 "cache not gitignored: should refuse to start"
fi

# Test 2: the case a grep cannot catch. The rule IS present, so a check that only
# reads .booth/.gitignore passes — but the files are already tracked, and gitignore
# does not apply to tracked files, so git keeps committing the credential.
PROJ_2="$(new_project tracked)"
printf 'cache/\n' > "$PROJ_2/.booth/.gitignore"
git -C "$PROJ_2" add -f .booth
git -C "$PROJ_2" commit -qm "committed the cache by accident"

run_guard "$PROJ_2"
if [[ "$GUARD_RC" -ne 0 ]] \
  && grep -q "tracked by git"      <<< "$GUARD_OUT" \
  && grep -q "git rm -r --cached"  <<< "$GUARD_OUT"; then
  check true 2 "cache tracked despite a cache/ rule: refuses, and names the untrack remedy"
else
  check false 2 "cache tracked despite a cache/ rule: should refuse and tell the user to untrack"
fi

# Test 3: the remedy the error printed actually clears it, and the cache still mounts.
git -C "$PROJ_2" rm -r --cached -q .booth/cache
run_guard "$PROJ_2"
if [[ "$GUARD_RC" -eq 0 ]] && grep -q "/home/coder/.claude" <<< "$GUARD_OUT"; then
  check true 3 "after untracking: starts, and the cache is still mounted"
else
  check false 3 "after untracking: should start with the cache mounted"
fi

# Test 4: nothing to commit to, so nothing to guard against.
PROJ_4="$(new_project no-git --no-git)"
run_guard "$PROJ_4"
if [[ "$GUARD_RC" -eq 0 ]]; then
  check true 4 "not a git repo: guard is skipped, booth starts"
else
  check false 4 "not a git repo: guard should be skipped"
fi

# Test 5: a cache entry that would shadow the project bind mount.
PROJ_5="$(new_project protected)"
printf 'cache/\n' > "$PROJ_5/.booth/.gitignore"
mkdir -p "$PROJ_5/.booth/cache/home/coder/code"
printf '' > "$PROJ_5/.booth/cache/home/coder/code/.mount-this"

run_guard "$PROJ_5"
if [[ "$GUARD_RC" -ne 0 ]] && grep -q "/home/coder/code" <<< "$GUARD_OUT"; then
  check true 5 "cache over a protected path: refuses to start and names the path"
else
  check false 5 "cache over a protected path: should refuse to start"
fi

exit $FAILED
