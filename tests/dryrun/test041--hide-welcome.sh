#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --hide-welcome / CB_HIDE_WELCOME / hide-welcome in config.toml all pass
#       BOOTH_HIDE_WELCOME=true into the container, which the shell profile
#       (99z-cb--profile.sh) reads to skip the welcome banner.
#
# Test 1: default → BOOTH_HIDE_WELCOME=false
# Test 2: --hide-welcome → BOOTH_HIDE_WELCOME=true
# Test 3: CB_HIDE_WELCOME=true → BOOTH_HIDE_WELCOME=true
# Test 4: hide-welcome = true in config.toml → BOOTH_HIDE_WELCOME=true
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

FAILED=0

check() {
  local num="$1" want="$2" desc="$3" actual="$4"
  if echo "$actual" | grep -qF -- "BOOTH_HIDE_WELCOME=$want"; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc (want BOOTH_HIDE_WELCOME=$want)"
    echo "$actual" | grep -o 'BOOTH_HIDE_WELCOME=[a-z]*' || echo "  (no BOOTH_HIDE_WELCOME in output)"
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: default
ACTUAL=$(run_coding_booth --dryrun --variant base -- sleep 1 2>&1 || true)
check 1 false "default leaves the banner on" "$ACTUAL"

# Test 2: flag
ACTUAL=$(run_coding_booth --dryrun --hide-welcome --variant base -- sleep 1 2>&1 || true)
check 2 true "--hide-welcome hides the banner" "$ACTUAL"

# Test 3: env var
ACTUAL=$(CB_HIDE_WELCOME=true run_coding_booth --dryrun --variant base -- sleep 1 2>&1 || true)
check 3 true "CB_HIDE_WELCOME=true hides the banner" "$ACTUAL"

# Test 4: config.toml
printf 'variant = "base"\nhide-welcome = true\n' > test--tmp-hide-welcome.toml
ACTUAL=$(run_coding_booth --config test--tmp-hide-welcome.toml --dryrun -- sleep 1 2>&1 || true)
check 4 true "hide-welcome = true in config.toml hides the banner" "$ACTUAL"

rm -f test--tmp-hide-welcome.toml

exit $FAILED
