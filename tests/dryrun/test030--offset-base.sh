#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --offset-base decouples +OFFSET host ports from the booth port.
#
# A "+OFFSET" host port counts from the booth port by default — that is what
# keeps two local booths of one project off each other's published ports. A booth
# that owns the whole port range has no such collision to dodge and a front door
# it does not choose, so --offset-base / CB_OFFSET_BASE / offset-base moves the
# base off the booth port.
#
# Test 1: no offset-base    → +4567:5672 follows the booth port (20000 → 24567)
# Test 2: --offset-base     → +4567:5672 counts from the base instead (34567)
# Test 3: offset-base 0     → +8090:8090 is the absolute port it names (8090)
# Test 4: CB_OFFSET_BASE    → the env var reaches the same place
# Test 5: config.toml       → offset-base as a file key
# Test 6: BOOTH_OFFSET_BASE → exported only when the base is not the booth port
#                             (booth--expose reads BOOTH_HOST_PORT otherwise)
# Test 7: ${NAME:-+OFFSET}  → a relative env fallback counts from the base too
# Test 8: --offset-base abc → rejected (must be a number)
# Test 9: --offset-base 70000 → rejected (out of range; 0 is not, see test 3)
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# Test 1: unset → the offset follows the booth port
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 -p '+4567:5672' -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 24567:5672'; then
  print_test_result "true" "$0" "1" "without offset-base, +4567 follows the booth port"
else
  print_test_result "false" "$0" "1" "without offset-base, +4567 should resolve to 24567"
  echo "$ACTUAL" | grep -- '-p' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 2: a base of its own is what the offset counts from, booth port aside
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 --offset-base 30000 -p '+4567:5672' -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 34567:5672' \
   && echo "$ACTUAL" | grep -qF -- '-p 127.0.0.1:20000:10000'; then
  print_test_result "true" "$0" "2" "--offset-base 30000 resolves +4567 to 34567, booth port unmoved"
else
  print_test_result "false" "$0" "2" "--offset-base 30000 should resolve +4567 to 34567"
  echo "$ACTUAL" | grep -- '-p' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 3: base 0 — legal here where a port of 0 is not — makes offsets absolute
ACTUAL=$(run_coding_booth --dryrun --variant base --port 20000 --offset-base 0 -p '+8090:8090' -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 8090:8090'; then
  print_test_result "true" "$0" "3" "--offset-base 0 makes +8090 the absolute port 8090"
else
  print_test_result "false" "$0" "3" "--offset-base 0 should make +8090 resolve to 8090"
  echo "$ACTUAL" | grep -- '-p' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 4: the env var, which is how a cloud host sets it for every booth it runs
ACTUAL=$(CB_OFFSET_BASE=40000 run_coding_booth --dryrun --variant base --port 20000 -p '+90:8090' -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 40090:8090'; then
  print_test_result "true" "$0" "4" "CB_OFFSET_BASE=40000 resolves +90 to 40090"
else
  print_test_result "false" "$0" "4" "CB_OFFSET_BASE=40000 should resolve +90 to 40090"
  echo "$ACTUAL" | grep -- '-p' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 5: as a config.toml key
printf 'variant = "base"\nport = "20000"\noffset-base = "50000"\nrun-args = ["-p", "+123:8123"]\n' > test--offset-base-config.toml

ACTUAL=$(run_coding_booth --config test--offset-base-config.toml --dryrun -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '-p 50123:8123'; then
  print_test_result "true" "$0" "5" "config.toml offset-base resolves +123 to 50123"
else
  print_test_result "false" "$0" "5" "config.toml offset-base should resolve +123 to 50123"
  echo "$ACTUAL" | grep -- '-p' | head -4
  FAILED=$((FAILED + 1))
fi

rm -f test--offset-base-config.toml

# Test 6: the container only hears about a base that has moved. booth--expose
# falls back to BOOTH_HOST_PORT, which is the same answer when it has not.
MOVED=$(run_coding_booth --dryrun --variant base --port 20000 --offset-base 30000 -- echo test 2>&1 | strip_ansi || true)
UNMOVED=$(run_coding_booth --dryrun --variant base --port 20000 -- echo test 2>&1 | strip_ansi || true)
if echo "$MOVED" | grep -qF -- "BOOTH_OFFSET_BASE=30000" \
   && ! echo "$UNMOVED" | grep -qF -- "BOOTH_OFFSET_BASE"; then
  print_test_result "true" "$0" "6" "BOOTH_OFFSET_BASE is exported only when the base moved"
else
  print_test_result "false" "$0" "6" "BOOTH_OFFSET_BASE should be exported only when the base moved"
  echo "$MOVED" | grep -i 'offset' | head -2
  echo "$UNMOVED" | grep -i 'offset' | head -2
  FAILED=$((FAILED + 1))
fi

# Test 7: a host-env fallback that is itself relative composes with the base —
# ${…} is expanded at TOML unmarshal, and the offset step then resolves what it
# produced.
printf 'variant = "base"\nport = "20000"\noffset-base = "50000"\nrun-args = ["--publish", "${SERVER_PORT:-+300}:9999"]\n' > test--offset-base-env.toml

ACTUAL=$(SERVER_PORT= run_coding_booth --config test--offset-base-env.toml --dryrun -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--publish 50300:9999'; then
  print_test_result "true" "$0" "7" "\${SERVER_PORT:-+300} falls back to the offset base, not the booth port"
else
  print_test_result "false" "$0" "7" "\${SERVER_PORT:-+300} should fall back to 50300"
  echo "$ACTUAL" | grep -- 'publish' | head -4
  FAILED=$((FAILED + 1))
fi

rm -f test--offset-base-env.toml

# Test 8: a non-numeric base is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --offset-base abc -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--offset-base must be a number'; then
  print_test_result "true" "$0" "8" "--offset-base abc is rejected (must be a number)"
else
  print_test_result "false" "$0" "8" "--offset-base abc should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

# Test 9: an out-of-range base is rejected
ACTUAL=$(run_coding_booth --dryrun --variant base --offset-base 70000 -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--offset-base must be between 0 and 65535'; then
  print_test_result "true" "$0" "9" "--offset-base 70000 is rejected (out of range)"
else
  print_test_result "false" "$0" "9" "--offset-base 70000 should be rejected"
  echo "$ACTUAL" | head -4
  FAILED=$((FAILED + 1))
fi

exit $FAILED
