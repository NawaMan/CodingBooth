#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: two published ports that cannot both bind
#
# Docker refuses to bind one host port twice ("address already in use") whichever
# way the duplicate arose, and its own message names neither port. NormalizePortMappings
# runs after +OFFSET resolution and refuses first, naming both mappings.
#
# Test 1: same host port, different container ports → error naming both
# Test 2: an offset that lands on an absolute mapping → error (only knowable at runtime)
# Test 3: a mapping that collides with the booth's own port → error
# Test 4: an identical mapping twice is redundant, not conflicting → deduped, booth runs
# Test 5: one container port on two host ports is legal → left alone
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# Test 1: same host port, two different container ports
printf 'variant = "base"\nport = "20000"\nrun-args = ["-p", "8978:8978", "--publish", "8978:9000"]\n' > test--tmp-conflict1.toml
ACTUAL=$(run_coding_booth --config test--tmp-conflict1.toml --dryrun -- echo test 2>&1 | strip_ansi || true)

if echo "$ACTUAL" | grep -qF -- 'host port 8978 is published twice' \
   && echo "$ACTUAL" | grep -qF -- '"8978:9000"'; then
  print_test_result "true" "$0" "1" "Same host port on two container ports is refused, naming both"
else
  print_test_result "false" "$0" "1" "Same host port on two container ports should be refused"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi
rm -f test--tmp-conflict1.toml

# Test 2: +8978 on a booth at 20000 is 28978, which an absolute mapping already claims.
# The strings differ, so only resolving the offset first can catch it.
printf 'variant = "base"\nport = "20000"\nrun-args = ["-p", "28978:8978", "-p", "+8978:9000"]\n' > test--tmp-conflict2.toml
ACTUAL=$(run_coding_booth --config test--tmp-conflict2.toml --dryrun -- echo test 2>&1 | strip_ansi || true)

if echo "$ACTUAL" | grep -qF -- 'host port 28978 is published twice'; then
  print_test_result "true" "$0" "2" "A +OFFSET landing on an absolute mapping is refused"
else
  print_test_result "false" "$0" "2" "A +OFFSET landing on an absolute mapping should be refused"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi
rm -f test--tmp-conflict2.toml

# Test 3: the booth publishes its own port, and it is added late in the run — a run-args
# mapping that lands on it would otherwise reach docker unchallenged.
printf 'variant = "base"\nport = "20000"\nrun-args = ["--publish", "20000:8978"]\n' > test--tmp-conflict3.toml
ACTUAL=$(run_coding_booth --config test--tmp-conflict3.toml --dryrun -- echo test 2>&1 | strip_ansi || true)

if echo "$ACTUAL" | grep -qF -- "the booth's own port"; then
  print_test_result "true" "$0" "3" "A mapping colliding with the booth's own port is refused"
else
  print_test_result "false" "$0" "3" "A mapping colliding with the booth's own port should be refused"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi
rm -f test--tmp-conflict3.toml

# Test 4: the same mapping twice is redundant, not conflicting — collapse it and run.
printf 'variant = "base"\nport = "20000"\nrun-args = ["-p", "8978:8978", "--publish", "8978:8978"]\n' > test--tmp-conflict4.toml
ACTUAL=$(run_coding_booth --config test--tmp-conflict4.toml --dryrun -- echo test 2>&1 | strip_ansi || true)
COUNT=$(echo "$ACTUAL" | grep -o -- '-p 8978:8978\|--publish 8978:8978' | wc -l)

if [ "$COUNT" = "1" ] && ! echo "$ACTUAL" | grep -qF 'published twice'; then
  print_test_result "true" "$0" "4" "An identical mapping twice is deduped, not refused"
else
  print_test_result "false" "$0" "4" "An identical mapping twice should be deduped (saw $COUNT)"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi
rm -f test--tmp-conflict4.toml

# Test 5: docker allows one container port on two host ports — we must not reject it.
printf 'variant = "base"\nport = "20000"\nrun-args = ["-p", "8978:8978", "-p", "19000:8978"]\n' > test--tmp-conflict5.toml
ACTUAL=$(run_coding_booth --config test--tmp-conflict5.toml --dryrun -- echo test 2>&1 | strip_ansi || true)

if echo "$ACTUAL" | grep -qF -- "-p 8978:8978" && echo "$ACTUAL" | grep -qF -- "-p 19000:8978" \
   && ! echo "$ACTUAL" | grep -qF 'published twice'; then
  print_test_result "true" "$0" "5" "One container port on two host ports is left alone"
else
  print_test_result "false" "$0" "5" "One container port on two host ports should be left alone"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi
rm -f test--tmp-conflict5.toml

exit $FAILED
