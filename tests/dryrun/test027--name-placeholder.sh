#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --name accepts {port} / {project} / {variant} placeholders, expanded
#       AFTER the port is chosen so the name can follow an auto-picked port.
#
# The project name here is the folder name ("dryrun"). A fixed --port keeps the
# resolved name deterministic.
#
# Test 1: {project}-{port}      → dryrun-7654
# Test 2: {variant}-{port}      → base-7654
# Test 3: a plain name is untouched
# Test 4: config.toml name template re-resolves on run
# Test 5: illegal literal characters are sanitized to a Docker-safe name
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

FAILED=0

# Test 1: {project}-{port}
ACTUAL=$(run_coding_booth --dryrun --variant base --port 7654 --name '{project}-{port}' -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--name dryrun-7654' \
   && echo "$ACTUAL" | grep -qF -- 'BOOTH_CONTAINER_NAME=dryrun-7654'; then
  print_test_result "true" "$0" "1" "{project}-{port} resolves to dryrun-7654"
else
  print_test_result "false" "$0" "1" "{project}-{port} should resolve to dryrun-7654"
  echo "$ACTUAL" | grep -iE 'name' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 2: {variant}-{port}
ACTUAL=$(run_coding_booth --dryrun --variant base --port 7654 --name '{variant}-{port}' -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--name base-7654'; then
  print_test_result "true" "$0" "2" "{variant}-{port} resolves to base-7654"
else
  print_test_result "false" "$0" "2" "{variant}-{port} should resolve to base-7654"
  echo "$ACTUAL" | grep -iE 'name' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 3: a plain name (no placeholder) is untouched
ACTUAL=$(run_coding_booth --dryrun --variant base --port 7654 --name fixed-name -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--name fixed-name'; then
  print_test_result "true" "$0" "3" "a plain name is left untouched"
else
  print_test_result "false" "$0" "3" "a plain name should be left untouched"
  echo "$ACTUAL" | grep -iE 'name' | head -4
  FAILED=$((FAILED + 1))
fi

# Test 4: a name template stored in config.toml re-resolves on run
printf 'variant = "base"\nport = "7654"\nname = "{project}-{port}"\n' > test--tmp-name.toml
ACTUAL=$(run_coding_booth --config test--tmp-name.toml --dryrun -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--name dryrun-7654'; then
  print_test_result "true" "$0" "4" "config.toml name template resolves on run"
else
  print_test_result "false" "$0" "4" "config.toml name template should resolve on run"
  echo "$ACTUAL" | grep -iE 'name' | head -4
  FAILED=$((FAILED + 1))
fi
rm -f test--tmp-name.toml

# Test 5: illegal literal characters are sanitized to a Docker-safe name
ACTUAL=$(run_coding_booth --dryrun --variant base --port 7654 --name 'my app:{port}' -- echo test 2>&1 | strip_ansi || true)
if echo "$ACTUAL" | grep -qF -- '--name my-app-7654'; then
  print_test_result "true" "$0" "5" "illegal literal characters are sanitized"
else
  print_test_result "false" "$0" "5" "illegal literal characters should be sanitized"
  echo "$ACTUAL" | grep -iE 'name' | head -4
  FAILED=$((FAILED + 1))
fi

exit $FAILED
