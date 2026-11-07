#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# build/strip-session-stamp.sh — the landing step that removes a worktree's session version stamp
# from its branch. Runs in throwaway git repos under a temp dir; needs only git, no Docker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRIP="$SCRIPT_DIR/../../build/strip-session-stamp.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; failures=$((failures + 1)); }
check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1"; echo "   expected: $2"; echo "   actual:   $3"; fi
}

new_repo() { # a main with version 0.82.0--rc1, then a session branch 'feat'
  local dir="$TMP/$1"
  mkdir -p "$dir" && cd "$dir"
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  printf '0.82.0--rc1\n' > version.txt
  printf '# X\n\n**Current Version:** v0.82.0--rc1\n\nbody\n' > README.md
  echo a > code.txt
  git add -A && git commit -qm init
  git checkout -qb feat
}
stamp() { sed -i -E "s/0\.82\.0--[a-z0-9]+/0.82.0--$1/" version.txt README.md; }

# --- 1. stamp commit, feature commits (one with a re-stamp + other README edit), restore commit,
#        while main moves on to --rc2. Landing = strip, then rebase.
new_repo full
stamp feat;  git commit -qam "chore: stamp worktree version"
echo b >> code.txt; git commit -qam "feature b"
echo c >> code.txt; sed -i 's/^body$/body edited/' README.md; stamp feat2
git commit -qam "feature c" -m "body line"
stamp rc1;   git commit -qam "chore: restore main version"
git checkout -q main; stamp rc2; git commit -qam "main moves to rc2"; git checkout -q feat

out=$("$STRIP" 2>&1) || fail "strip exits 0"
git rebase -q main >/dev/null 2>&1 || fail "rebase after strip has no conflict"
check "only feature commits remain" "feature c|feature b" "$(git log --format=%s main..feat | paste -sd'|')"
check "commit body kept"            "body line"           "$(git log -1 --format=%b feat | head -1)"
check "branch carries no version change" "" "$(git diff main feat -- version.txt)"
check "README keeps main's version line" "**Current Version:** v0.82.0--rc2" "$(grep -F 'Current Version' README.md)"
check "README keeps the other edit"      "body edited" "$(grep -F 'body' README.md)"
check "report names the cleaned commit"  "1" "$(grep -c 'cleaned  .* feature c' <<<"$out")"
check "report names both dropped commits" "2" "$(grep -c '^  dropped  ' <<<"$out")"

# --- 2. a second run has nothing to do.
check "re-run is a no-op" "strip-session-stamp: nothing to strip on 'feat'" "$("$STRIP" 2>&1)"

# --- 3. stamp folded into the first feature commit (no separate stamp commit).
new_repo folded
stamp feat; echo s >> code.txt; git commit -qam "feature s"
stamp rc1;  git commit -qam "chore: restore main version"
"$STRIP" >/dev/null 2>&1
check "folded stamp: one commit left"       "feature s" "$(git log --format=%s main..feat)"
check "folded stamp: only the feature diff" "code.txt"  "$(git diff --name-only main feat)"

# --- 4. a branch with nothing but the stamp collapses onto main.
new_repo only-stamp
stamp feat; git commit -qam "chore: stamp"
"$STRIP" >/dev/null 2>&1
check "stamp-only branch: no commits left" "0" "$(git rev-list --count main..feat)"

# --- 5. refusals leave the branch untouched.
new_repo refuse
stamp feat; git commit -qam "chore: stamp"
tip=$(git rev-parse HEAD)
echo dirty >> code.txt
if "$STRIP" >/dev/null 2>&1; then fail "dirty tree is refused"; else pass "dirty tree is refused"; fi
check "refusal leaves the branch alone" "$tip" "$(git rev-parse HEAD)"
git checkout -q code.txt
git checkout -q main
if "$STRIP" >/dev/null 2>&1; then fail "running on main is refused"; else pass "running on main is refused"; fi

echo
if [[ $failures -eq 0 ]]; then echo "All strip-session-stamp checks passed"; else echo "$failures check(s) failed"; exit 1; fi
