#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Release check: no test fixture or example in this repo carries a copy of a
# built-in setup in its .booth/setups/.
#
# A project's .booth/setups/ goes first on PATH in the booth image
# (cli/src/pkg/boothfile/compiler.go, ProjectSetupsPath), so a file there with
# the name of a built-in -- variants/base/setups/<path> -- runs instead of it.
# For a user that is a feature (docs/BOOTH_CUSTOMIZATION.md). In this repo it
# means a test or example exercises its own copy, which drifts, rather than the
# setup the image ships: 28 complex tests did exactly that until 2026-11-01.
# Scripts a project genuinely adds under its own name (lamp-init--setup.sh) are
# fine.
#
#   build/check-setup-shadowing.sh            # this repo (release-push, CI, tests)
#   build/check-setup-shadowing.sh <root>     # another tree (the guard's own test)
#
# Exit 0 when nothing shadows, 1 with one line per offending file otherwise.

set -Eeuo pipefail

ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
BUILTINS="$ROOT/variants/base/setups"
[[ -d "$BUILTINS" ]] || { echo "❌ No built-in setups at ${BUILTINS}" >&2; exit 2; }

# Tracked and untracked-but-not-ignored files, so a copy made while developing
# is caught before it is committed; nested worktrees (worktree/, gitignored) are
# other checkouts and are left out. Outside git (a test fixture) every file counts.
list_files() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" ls-files -co --exclude-standard
  else
    (cd "$ROOT" && find . -path ./worktree -prune -o -type f -print | sed 's#^\./##')
  fi
}

found=0
while IFS= read -r f; do
  [[ "$f" == */.booth/setups/* ]] || continue
  [[ "$f" == variants/* ]] && continue
  [[ -f "$ROOT/$f" ]] || continue   # deleted in the work tree, not yet staged
  rel="${f#*/.booth/setups/}"
  if [[ -f "$BUILTINS/$rel" ]]; then
    [[ $found -eq 0 ]] && echo "❌ These .booth/setups/ files shadow a built-in setup of the same name:"
    echo "   $f  (shadows variants/base/setups/$rel)"
    found=$((found + 1))
  fi
done < <(list_files)

if [[ $found -gt 0 ]]; then
  cat <<'MSG'

   The copy runs instead of the setup the image ships, so the test or example
   stops testing the catalog. Fix variants/base/setups/ instead and delete the
   copy; a script the project adds should have a name of its own.
MSG
  exit 1
fi
echo "✅ No .booth/setups/ file shadows a built-in setup."
