#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the GitHub star prompt reaches the booth as BOOTH_STAR_PROMPT
#
# The overlay asks for a GitHub star after a while in a booth's web UI, until
# the link is clicked in some booth on this host. The CLI tells each booth
# which: on, off (CB_STAR_PROMPT=off) or done (the user-wide marker exists).
#
#   Test 1: No marker, nothing set → BOOTH_STAR_PROMPT=on.
#   Test 2: The marker in the config folder → done.
#   Test 3: CB_STAR_PROMPT=off → off, even with the marker.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }
prompt_of() { grep -oE 'BOOTH_STAR_PROMPT=[^ '"'"'"]*' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

FAILED=0
check() {
  local num="$1" desc="$2" got="$3" want="$4"
  if [[ "$got" == "$want" ]]; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc"
    echo "  want: $want"
    echo "  got:  ${got:-(none)}"
    FAILED=$((FAILED + 1))
  fi
}

# A config folder of its own, so the user's real marker does not leak in.
CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT

run() { XDG_CONFIG_HOME="$CONF" run_coding_booth --variant base --dryrun 2>/dev/null | strip_ansi | prompt_of; }

check 1 "No marker → BOOTH_STAR_PROMPT=on" "$(CB_STAR_PROMPT= run)" "BOOTH_STAR_PROMPT=on"

mkdir -p "$CONF/codingbooth"
touch "$CONF/codingbooth/github-star"
check 2 "The link was clicked before (marker) → done" "$(CB_STAR_PROMPT= run)" "BOOTH_STAR_PROMPT=done"

check 3 "CB_STAR_PROMPT=off → off, marker or not" "$(CB_STAR_PROMPT=off run)" "BOOTH_STAR_PROMPT=off"

[[ "$FAILED" -eq 0 ]] || exit 1
