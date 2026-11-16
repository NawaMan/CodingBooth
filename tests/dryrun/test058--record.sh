#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --record / CB_RECORD / record in config.toml all pass BOOTH_RECORD=true
#       into the container, which is what turns the session recorder on there
#       (booth--lifecycle-log, 99z-cb--profile.sh, booth--record).
#
# Test 1: default → no BOOTH_RECORD at all (a booth that is not recorded has no
#         trace of the feature)
# Test 2: --record → BOOTH_RECORD=true
# Test 3: CB_RECORD=true → BOOTH_RECORD=true
# Test 4: record = true in config.toml → BOOTH_RECORD=true
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

FAILED=0

check() {
  local num="$1" want="$2" desc="$3" actual="$4" has=false
  if echo "$actual" | grep -qF -- "BOOTH_RECORD=true"; then has=true; fi
  if [[ "$has" == "$want" ]]; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc (want BOOTH_RECORD=true present: $want)"
    echo "$actual" | grep -o 'BOOTH_RECORD=[a-z]*' || echo "  (no BOOTH_RECORD in output)"
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: default
ACTUAL=$(run_coding_booth --dryrun --variant base -- sleep 1 2>&1 || true)
check 1 false "default does not record" "$ACTUAL"

# Test 2: --record flag
ACTUAL=$(run_coding_booth --dryrun --record --variant base -- sleep 1 2>&1 || true)
check 2 true "--record turns the recorder on" "$ACTUAL"

# Test 3: CB_RECORD env var
ACTUAL=$(CB_RECORD=true run_coding_booth --dryrun --variant base -- sleep 1 2>&1 || true)
check 3 true "CB_RECORD=true turns the recorder on" "$ACTUAL"

# Test 4: record = true in config.toml
printf 'variant = "base"\nrecord = true\n' > test--tmp-record.toml
ACTUAL=$(run_coding_booth --config test--tmp-record.toml --dryrun -- sleep 1 2>&1 || true)
check 4 true "record = true in config.toml turns the recorder on" "$ACTUAL"

rm -f test--tmp-record.toml

exit "$FAILED"
