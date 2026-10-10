#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Cache and Shared seeds reach a real booth, across a git clone
#
# A seed in .booth/cache-seed/ or .booth/shared-seed/ is the first content of a
# Cache or Shared path; booth copies it in only while the path is missing or
# empty. The seed folders are committed and .booth/cache/ is not, so a fresh
# clone must get the Cache content back from its seed.
#
# The project is a git repo outside this one (this repo gitignores
# **/.booth/cache/). Its .booth/ is booth config output, from a project-local
# template that ships file seeds with [files.cache-seed] / [files.shared-seed];
# a folder seed is placed in .booth/cache-seed/ by hand.
#
# 1) booth config fills the declared paths from the seeds
# 2) A booth sees the seeds, and a path with no seed is empty
# 3) Edits made in the booth survive the next start: no re-seed over content,
#    and a file deleted from a seeded folder stays deleted
# 4) A git clone has no .booth/cache/; its first booth starts with the seeds
#    again, and with the Shared edit that was committed
# 5) A Shared file emptied on the host is seeded again
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Cache and Shared seeds ==="

FAILED=0

# The booth runs from a project outside the repo, so resolve the binary here, as
# test-cache-gitignore-guard does. (SCRIPT_DIR is tests/complex/<category>/<test>.)
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BOOTH_BIN="$REPO_ROOT/codingbooth"
if [[ ! -x "$BOOTH_BIN" ]]; then
  echo "ERROR: codingbooth not found at $BOOTH_BIN — build it first" >&2
  exit 1
fi
# A worktree or --rc version has no released catalog to fetch.
export CB_TEMPLATES_PATH="$REPO_ROOT/templates"

WORK_DIR="$(mktemp -d)"
PROJ="$WORK_DIR/seed-proj-$RANDOM"
CLONE="$WORK_DIR/seed-clone-$RANDOM"
cleanup() {
  docker rm -f "$(basename "$PROJ")" "$(basename "$CLONE")" >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

SETTINGS=home/coder/.config/tool/settings.json
STATE=home/coder/.tool/state.json
HISTORY=home/coder/.tool_history

# in_booth <project> <command> — run one command in a one-shot booth of that project.
in_booth() {
  (cd "$1" && "$BOOTH_BIN" -- "$2" 2>/dev/null) || true
}

# check <case> <description> <expected> <actual>
check() {
  if [[ "$4" == "$3" ]]; then
    print_test_result "true" "$0" "$1" "$2"
  else
    print_test_result "false" "$0" "$1" "$2"
    echo "  Expected: $3"
    echo "  Actual:   $4"
    FAILED=$((FAILED + 1))
  fi
}

# read_paths <project> — the four seeded paths as the booth sees them, one line each.
read_paths() {
  in_booth "$1" "for f in /$SETTINGS /$STATE /home/coder/.toolcfg/a.txt /$HISTORY; do printf '%s|' \"\$(cat \$f 2>/dev/null || echo MISSING)\"; done; echo" \
    | tr -d '\r' | grep '|' | tail -1 || true
}

# --- The project: a template with file seeds, a hand-placed folder seed -------
mkdir -p "$PROJ/.booth/templates" "$PROJ/.booth/cache-seed/home/coder/.toolcfg"
cat > "$PROJ/.booth/templates/seeded.toml" <<'TOML'
cache-files  = ["home/coder/.tool/state.json", "home/coder/.tool_history"]
cache-dirs   = ["home/coder/.toolcfg"]
shared-files = ["home/coder/.config/tool/settings.json"]

[files.cache-seed]
"home/coder/.tool/state.json" = "STATE_SEED"

[files.shared-seed]
"home/coder/.config/tool/settings.json" = "SETTINGS_SEED"
TOML
: > "$PROJ/.booth/cache-seed/home/coder/.toolcfg/.mount-this"
echo "A_SEED" > "$PROJ/.booth/cache-seed/home/coder/.toolcfg/a.txt"
echo "B_SEED" > "$PROJ/.booth/cache-seed/home/coder/.toolcfg/b.txt"

git -C "$PROJ" init -q
git -C "$PROJ" config user.email "test@example.com"
git -C "$PROJ" config user.name  "Test"

# 1) booth config fills the declared paths from the seeds.
(cd "$PROJ" && "$BOOTH_BIN" config --no-tui --select seeded >/dev/null 2>&1) || true
check 1 "booth config fills a Shared path from its seed" \
  "SETTINGS_SEED" "$(cat "$PROJ/.booth/shared/$SETTINGS" 2>/dev/null || echo MISSING)"

# 2) A booth sees the seeds; the path with no seed is empty.
check 2 "the booth starts with the Shared, Cache and folder seeds" \
  "SETTINGS_SEED|STATE_SEED|A_SEED||" "$(read_paths "$PROJ")"

# 3) Edits in the booth survive the next start.
in_booth "$PROJ" "echo SETTINGS_EDITED > /$SETTINGS; echo STATE_EDITED > /$STATE; rm /home/coder/.toolcfg/b.txt" >/dev/null
check 3 "edits survive a restart: no re-seed over content" \
  "SETTINGS_EDITED|STATE_EDITED|A_SEED||" "$(read_paths "$PROJ")"
check 4 "a file deleted from a seeded folder stays deleted" \
  "MISSING" "$(in_booth "$PROJ" "cat /home/coder/.toolcfg/b.txt 2>/dev/null || echo MISSING" | tr -d '\r' | tail -1)"

# 4) A git clone starts with the seeds again.
git -C "$PROJ" add -A
git -C "$PROJ" commit -qm "booth with seeds"
git clone -q "$PROJ" "$CLONE"
if [[ -e "$CLONE/.booth/cache" ]]; then
  check 5 "a clone has no .booth/cache/ (gitignored)" "absent" "present"
else
  check 5 "a clone has no .booth/cache/ (gitignored)" "absent" "absent"
fi
check 6 "the clone's booth gets the Cache seeds and the committed Shared edit" \
  "SETTINGS_EDITED|STATE_SEED|A_SEED||" "$(read_paths "$CLONE")"
check 7 "the clone's seeded folder is whole again" \
  "B_SEED" "$(in_booth "$CLONE" "cat /home/coder/.toolcfg/b.txt 2>/dev/null || echo MISSING" | tr -d '\r' | tail -1)"

# 5) A Shared file emptied on the host is seeded again.
: > "$CLONE/.booth/shared/$SETTINGS"
check 8 "an emptied Shared file is seeded again" \
  "SETTINGS_SEED|STATE_SEED|A_SEED||" "$(read_paths "$CLONE")"

exit $FAILED
