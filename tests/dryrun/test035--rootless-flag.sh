#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# --rootless is a booth flag (skip the Linux rootless refusal). It must not be
# forwarded as a docker run argument.

OUT=$(run_coding_booth --variant base --dryrun --rootless -- true)

if printf '%s\n' "$OUT" | grep -E '(^|[[:space:]])--rootless([[:space:]]|$)' | grep -q docker; then
  print_test_result "false" "$0" "1" "--rootless is not passed through to docker"
  echo "Actual:"; echo "$OUT"
  exit 1
fi

# The docker command itself should still be printed.
if printf '%s\n' "$OUT" | grep -q 'docker'; then
  print_test_result "true" "$0" "1" "--rootless is not passed through to docker"
else
  print_test_result "false" "$0" "1" "--rootless dryrun still prints a docker command"
  echo "Actual:"; echo "$OUT"
  exit 1
fi
