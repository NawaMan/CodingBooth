#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# --quiet hides the daemon banner / visit URL / container-id line, but still
# prints the docker command in dryrun. --silence-build alone does not hide them:
# a `booth --silence-build --daemon` still needs the URL.

QUIET_OUT=$(run_coding_booth --variant base --dryrun --daemon --quiet -- tree -C)
SILENCE_OUT=$(run_coding_booth --variant base --dryrun --daemon --silence-build -- tree -C)

if printf '%s\n' "$QUIET_OUT" | grep -q '📦 Running booth in daemon mode'; then
  print_test_result "false" "$0" "1" "--quiet hides the daemon banner"
  echo "Actual:"; echo "$QUIET_OUT"
  exit 1
fi
print_test_result "true" "$0" "1" "--quiet hides the daemon banner"

if printf '%s\n' "$QUIET_OUT" | grep -q "Visit '"; then
  print_test_result "false" "$0" "2" "--quiet hides the visit URL"
  echo "Actual:"; echo "$QUIET_OUT"
  exit 1
fi
print_test_result "true" "$0" "2" "--quiet hides the visit URL"

if printf '%s\n' "$QUIET_OUT" | grep -q 'Container ID'; then
  print_test_result "false" "$0" "3" "--quiet hides the container-id line"
  echo "Actual:"; echo "$QUIET_OUT"
  exit 1
fi
print_test_result "true" "$0" "3" "--quiet hides the container-id line"

if printf '%s\n' "$QUIET_OUT" | grep -q 'docker'; then
  print_test_result "true" "$0" "4" "--quiet dryrun still prints the docker command"
else
  print_test_result "false" "$0" "4" "--quiet dryrun still prints the docker command"
  echo "Actual:"; echo "$QUIET_OUT"
  exit 1
fi

if printf '%s\n' "$SILENCE_OUT" | grep -q '📦 Running booth in daemon mode'; then
  print_test_result "true" "$0" "5" "--silence-build --daemon still prints the banner"
else
  print_test_result "false" "$0" "5" "--silence-build --daemon still prints the banner"
  echo "Actual:"; echo "$SILENCE_OUT"
  exit 1
fi

# A daemon run with no command prints the port banner when the port is generated
# (NEXT). --quiet must hide it; without --quiet it must still appear. (A command
# after -- skips the banner anyway — that is command mode.)
NEXT_QUIET=$(run_coding_booth --variant base --dryrun --daemon --quiet --port NEXT)
NEXT_LOUD=$(run_coding_booth --variant base --dryrun --daemon --port NEXT)

if printf '%s\n' "$NEXT_QUIET" | grep -q 'BOOTH PORT SELECTED'; then
  print_test_result "false" "$0" "6" "--quiet hides the port-selection banner"
  echo "Actual:"; echo "$NEXT_QUIET"
  exit 1
fi
print_test_result "true" "$0" "6" "--quiet hides the port-selection banner"

if printf '%s\n' "$NEXT_LOUD" | grep -q 'BOOTH PORT SELECTED'; then
  print_test_result "true" "$0" "7" "daemon --port NEXT still prints the port banner"
else
  print_test_result "false" "$0" "7" "daemon --port NEXT still prints the port banner"
  echo "Actual:"; echo "$NEXT_LOUD"
  exit 1
fi
