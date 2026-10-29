#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# check-example.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# The generic check, for any example without a check-<example>.sh of its own.
# Run as the real user, as the command booth-entry ends with, from the
# example's folder:
#   - the base image's tools and the booth-entry user steps;
#   - every one of the example's own .cb-tests/inBooth-test*.sh, each in a
#     login shell. BOOTH_CONTAINER_NAME is set so the example's Justfile runs
#     its recipes here instead of starting a booth.
# Appends to $REPORT.
# -----------------------------------------------------------------------------

set -uo pipefail

REPORT="${REPORT:-$HOME/host-provision-report.txt}"
export BOOTH_CONTAINER_NAME="${BOOTH_CONTAINER_NAME:-host-provision}"
FAILS=0

check() {   # check <label> <command>   (login shell)
  local label="$1" cmd="$2" out rc
  out="$(bash -lc "$cmd" 2>&1 < /dev/null)"; rc=$?
  out="$(printf '%s' "$out" | grep -v '^\s*$' | tail -n 1 | cut -c1-110)"
  if [ "$rc" -eq 0 ]; then
    printf 'PASS  %-46s %s\n' "$label" "$out" | tee -a "$REPORT"
  else
    printf 'FAIL  %-46s %s\n' "$label" "$out" | tee -a "$REPORT"
    FAILS=$((FAILS + 1))
  fi
}

echo "== checks as $(id -un) (uid $(id -u)), HOME=$HOME, cwd=$PWD" | tee -a "$REPORT"

check "base: just"                  'command -v just'
check "base: lazygit"               'command -v lazygit'
check "base: gpg 2.5"               'gpg --version | head -n 1 | grep -q " 2\.5\." && gpg --version | head -n 1'
check "base: setups dir on PATH"    'command -v go--setup.sh'
check "startup log written"         'grep -c "Running startup script" /tmp/startups.log'
check "rc profile block present"    'grep -q "CodingBooth profile" "$HOME/.bashrc" && echo ok'

shopt -s nullglob
tests=(.cb-tests/inBooth-test[0-9][0-9][0-9]-*.sh)
# 38 of the 96 examples have in-booth tests; the rest are provisioned but unverified.
[ "${#tests[@]}" -gt 0 ] || echo "UNTESTED  no .cb-tests/inBooth-test*.sh in $PWD" | tee -a "$REPORT"
for t in "${tests[@]}"; do
  check "example: $(basename "$t" .sh)" "bash '$t'"
done

echo "== $FAILS failed check(s)" | tee -a "$REPORT"
exit 0
