#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a --public booth that already has an extra port published is refused
# unless --ok-public says the caller means it
#
# --public gets the booth's own port a password and TLS; any other published
# port (a template's +expose, a config-time --expose, plain run-args) has
# neither. CheckPublicPortsExposed refuses to start in that combination
# unless --ok-public is also given -- and even then, still warns rather than
# staying silent about the tradeoff.
#
# Test 1: --public + an exposed port, no --ok-public -> refused, naming both
#         the port and --ok-public, and never reaching the docker command
# Test 2: --public + an exposed port + --ok-public -> proceeds and warns,
#         naming both ports
# Test 3: --public, no exposed port -> proceeds, no warning needed
# Test 4: an exposed port, not --public -> proceeds, no warning
# Test 5: --public --ok-public --quiet + an exposed port -> proceeds silently
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

cleanup() {
  rm -f test--public-warn-config*.toml
}
trap cleanup EXIT

# Test 1: refused without --ok-public. Capture the exit code explicitly (per
# tests/README.md: a failing pipeline inside $( ) under set -e would otherwise
# abort this script on the very case being tested).
printf 'variant = "base"\nrun-args = ["-p", "18080:80"]\n' > test--public-warn-config1.toml

RC=0
ACTUAL=$(echo testpw | run_coding_booth --config test--public-warn-config1.toml --dryrun --public --port 13000 -- echo test 2>&1 | strip_ansi) || RC=$?

if [ "$RC" -ne 0 ] \
  && echo "$ACTUAL" | grep -q -- "--ok-public" \
  && echo "$ACTUAL" | grep -q "18080" \
  && echo "$ACTUAL" | grep -q "13000" \
  && ! echo "$ACTUAL" | grep -q "^    run \\\\$"; then
  print_test_result "true" "$0" "1" "public booth with an exposed port is refused without --ok-public"
else
  print_test_result "false" "$0" "1" "public booth with an exposed port should be refused without --ok-public"
  echo "  Exit: $RC"
  echo "  Actual:"
  echo "$ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: --ok-public proceeds, and still warns naming both ports (an
# acknowledged tradeoff is not the same as an invisible one).
printf 'variant = "base"\nrun-args = ["-p", "18080:80"]\n' > test--public-warn-config2.toml

ACTUAL=$(echo testpw | run_coding_booth --config test--public-warn-config2.toml --dryrun --public --ok-public --port 13000 -- echo test 2>&1 | strip_ansi)

if echo "$ACTUAL" | grep -q "This booth is public" && echo "$ACTUAL" | grep -q "18080" && echo "$ACTUAL" | grep -q "13000"; then
  print_test_result "true" "$0" "2" "--ok-public proceeds and warns, naming both ports"
else
  print_test_result "false" "$0" "2" "--ok-public should proceed and warn, naming both ports"
  echo "  Actual:"
  echo "$ACTUAL" | grep -i "public\|18080\|13000" || echo "  (no matching lines)"
  FAILED=$((FAILED + 1))
fi

# Test 3: --public with nothing else exposed needs no --ok-public and prints
# no warning (the pre-existing PUBLIC banner still prints -- only this check
# is at issue).
printf 'variant = "base"\n' > test--public-warn-config3.toml

ACTUAL=$(echo testpw | run_coding_booth --config test--public-warn-config3.toml --dryrun --public --port 13000 -- echo test 2>&1 | strip_ansi)

if echo "$ACTUAL" | grep -q "This booth is public"; then
  print_test_result "false" "$0" "3" "public booth with nothing else exposed should not warn or refuse"
  echo "  Actual:"
  echo "$ACTUAL" | grep -i "public"
  FAILED=$((FAILED + 1))
else
  print_test_result "true" "$0" "3" "public booth with nothing else exposed proceeds without --ok-public"
fi

# Test 4: an exposed port on a non-public booth is the existing, unprotected-
# by-design behavior -- no warning and no refusal, since there is no
# protected front door to contrast it with.
printf 'variant = "base"\nrun-args = ["-p", "18080:80"]\n' > test--public-warn-config4.toml

ACTUAL=$(run_coding_booth --config test--public-warn-config4.toml --dryrun --port 13000 -- echo test 2>&1 | strip_ansi)

if echo "$ACTUAL" | grep -q "This booth is public"; then
  print_test_result "false" "$0" "4" "a non-public booth with an exposed port should not warn"
  echo "  Actual:"
  echo "$ACTUAL" | grep -i "public"
  FAILED=$((FAILED + 1))
else
  print_test_result "true" "$0" "4" "a non-public booth with an exposed port stays quiet"
fi

# Test 5: --quiet suppresses the warning text but the refusal itself is not
# gated on --quiet (a safety check, not informational chatter) -- with
# --ok-public there is nothing left to refuse, so this proceeds silently.
printf 'variant = "base"\nrun-args = ["-p", "18080:80"]\n' > test--public-warn-config5.toml

ACTUAL=$(echo testpw | run_coding_booth --config test--public-warn-config5.toml --dryrun --public --ok-public --quiet --port 13000 -- echo test 2>&1 | strip_ansi)

if echo "$ACTUAL" | grep -q "This booth is public"; then
  print_test_result "false" "$0" "5" "--quiet should suppress the warning text"
  echo "  Actual:"
  echo "$ACTUAL" | grep -i "public"
  FAILED=$((FAILED + 1))
else
  print_test_result "true" "$0" "5" "--ok-public --quiet proceeds silently"
fi

exit $FAILED
