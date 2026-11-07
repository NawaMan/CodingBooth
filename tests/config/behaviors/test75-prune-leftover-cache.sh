#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Deselecting a cache extension leaves its folders in .booth/cache/ (booth config never deletes
# data). They are no longer declared, so booth no longer mounts them, and `booth prune cache`
# deletes them -- after asking, and only those: a declared path stays. Host-only, no container.

source "$(dirname "$0")/../test-helpers--source.sh"

begin

# check <label> <command...>: a test that passes when the command does.
check() {
  local label="$1"; shift
  TEST_COUNT=$((TEST_COUNT + 1))
  local pad
  pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
  echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
  if "$@"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
  fi
}

cache="$prj/.booth/cache/home/coder"

run rm -Rf "$prj" ; mkdir -p "$prj"
run booth config "$prj" --no-tui --select "shell-history/envfolio+store-cache"
echo "KEY" > "$cache/.gnupg/key"   # something worth asking about

# Deselect +store-cache: config.toml forgets the folders, the folders stay.
run booth config "$prj" --no-tui --overwrite --select "shell-history/envfolio"
check "deselecting keeps the cached ~/.gnupg"           test -f "$cache/.gnupg/key"
check "config.toml no longer declares it"               bash -c "! grep -q 'gnupg' '$prj/.booth/config.toml'"

# No --yes and nothing answered (no terminal): it lists, asks, and deletes nothing.
out="$(cd "$prj" && booth prune cache </dev/null 2>&1)"
echo "$out" >> "$log"
check "prune lists the leftover folder"                 grep -q '.booth/cache/home/coder/.gnupg/' <<< "$out"
check "prune asks before deleting"                      grep -q 'Prune cancelled.' <<< "$out"
check "an unanswered prune deletes nothing"             test -f "$cache/.gnupg/key"

# --yes, from elsewhere with --code: the leftovers go, declared history files stay.
out="$(booth prune cache --yes --code "$prj" 2>&1)"
echo "$out" >> "$log"
check "prune --yes deletes ~/.gnupg"                    test ! -e "$cache/.gnupg"
check "prune --yes deletes the store folder"            test ! -e "$cache/.local"
check "a declared cache file stays"                     test -f "$cache/.bash_history"
check "prune says how many it deleted"                  grep -q 'Deleted 2 item(s) from .booth/cache/' <<< "$out"

out="$(booth prune share --yes --code "$prj" 2>&1)"
echo "$out" >> "$log"
check "share is shared; nothing there to prune"         grep -q 'Nothing to prune' <<< "$out"

refuses_unknown_target() { ! booth prune volumes >/dev/null 2>&1; }
check "an unknown prune target is refused"              refuses_unknown_target

finally
