#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: `booth print-security-warning` prints the warning a run would show and
#       exits 1, or prints "No security warning." and exits 0. Nothing starts.
#       A run (here --dryrun) records the same reasons on the container label
#       cb.security-warning, which start/shell/exec read to warn again.
#
# Test 1: plain booth → "No security warning.", exit 0
# Test 2: --privileged → the reason, its impact, its link, exit 1
# Test 3: run-args in config.toml (writable /etc) → host-mounts reason, exit 1
# Test 4: --dind --dind-allowed → still reported (the flag skips the question only)
# Test 5: --dryrun --privileged → the run command carries the cb.security-warning label
# Test 6: --dind on Docker Engine (Linux) points at --dind-isolation; on a VM engine
#         (Docker Desktop: macOS, Windows) it does not, since Kata is not available there
# Test 7: --dind-isolation → nothing to report where Kata runs; the fallback where it does not
# Test 8: --dind-isolation with Kata hidden → the fallback banner and the --dind warning
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

FAILED=0
DOC="https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md"

check() {
  local num="$1" desc="$2" want_exit="$3" got_exit="$4" output="$5"; shift 5
  local ok=true want
  [[ "$got_exit" == "$want_exit" ]] || ok=false
  for want in "$@"; do
    echo "$output" | grep -qF -- "$want" || ok=false
  done
  if [[ "$ok" == true ]]; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc (want exit $want_exit and: $*)"
    echo "  exit: $got_exit"
    echo "$output" | sed 's/^/  | /'
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: nothing dangerous
EXIT=0; OUT=$(run_coding_booth print-security-warning --variant base 2>/dev/null) || EXIT=$?
check 1 "plain booth has no warning" 0 "$EXIT" "$OUT" "No security warning."

# Test 2: a run-arg on the command line
EXIT=0; OUT=$(run_coding_booth print-security-warning --variant base --privileged 2>/dev/null) || EXIT=$?
# "get root" and not the rest of the line: the impact is worded for where a way out lands on
# this engine (the host, an engine VM, the WSL 2 VM), which depends on the machine the suite runs
# on. The per-engine wording is pinned in cli/src/pkg/hostescape/hostescape_test.go.
check 2 "--privileged is reported with its impact and link" 1 "$EXIT" "$OUT" \
  "  - --privileged" "get root" "$DOC#kernel-access" \
  "This only matters if the booth runs code you do not trust."

# Test 3: run-args from config.toml
printf 'variant = "base"\nrun-args = ["-v", "/etc:/host-etc"]\n' > test--tmp-security-warning.toml
EXIT=0; OUT=$(run_coding_booth print-security-warning --config test--tmp-security-warning.toml 2>/dev/null) || EXIT=$?
check 3 "config.toml run-args are read" 1 "$EXIT" "$OUT" "writable mount of host /etc" "$DOC#host-mounts"
rm -f test--tmp-security-warning.toml

# Test 4: the allowed flag does not hide it
EXIT=0; OUT=$(run_coding_booth print-security-warning --variant base --dind --dind-allowed 2>/dev/null) || EXIT=$?
check 4 "--dind-allowed does not hide --dind" 1 "$EXIT" "$OUT" "--dind (privileged Docker-in-Docker sidecar)" "$DOC#dind"

# Test 5: the run records the reasons on the container
EXIT=0; OUT=$(run_coding_booth --dryrun --variant base --privileged -- sleep 1 2>&1) || EXIT=$?
# A prefix, left open before the closing brace: the reason also carries "where" on an engine
# whose way out does not land on the host itself.
check 5 "a run labels the container with its reasons" 0 "$EXIT" "$OUT" \
  'cb.security-warning=[{"kind":"kernel-access","what":"--privileged"'

# Test 6: the --dind hint, only where the warning says "this machine"
EXIT=0; OUT=$(run_coding_booth print-security-warning --variant base --dind 2>/dev/null) || EXIT=$?
if [[ "$(uname -s)" == "Linux" ]] && ! docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -q "Docker Desktop"; then
  check 6 "--dind on Docker Engine points at --dind-isolation kata" 1 "$EXIT" "$OUT" "--dind-isolation kata" "$DOC#dind-isolation"
elif echo "$OUT" | grep -qF -- "--dind-isolation"; then
  check 6 "--dind on a VM engine does not offer --dind-isolation" 1 "$EXIT" "$OUT" "(no --dind-isolation hint expected)"
else
  check 6 "--dind on a VM engine does not offer --dind-isolation" 1 "$EXIT" "$OUT"
fi

# Test 7: a Kata sidecar has nothing to report — where this machine can run it. Where it
#         cannot, the run would fall back to the privileged sidecar, and that is reported.
EXIT=0; OUT=$(run_coding_booth print-security-warning --variant base --dind-isolation 2>/dev/null) || EXIT=$?
if kata_supported 2>/dev/null; then
  check 7 "--dind-isolation reports no security warning (Kata runs here)" 0 "$EXIT" "$OUT" "No security warning."
else
  check 7 "--dind-isolation without Kata reports the fallback" 1 "$EXIT" "$OUT" \
    "NOT AVAILABLE ON THIS MACHINE" "--dind (privileged Docker-in-Docker sidecar)"
fi

# Test 8: Kata out of reach (its shim hidden from PATH, as on a Linux host without Kata):
#         the fallback banner and the --dind warning, so a real run would ask first.
TMP_BIN=$(mktemp -d)
ln -s "$(command -v docker)" "$TMP_BIN/docker"
EXIT=0; OUT=$(PATH="$TMP_BIN:/usr/bin:/bin" run_coding_booth print-security-warning --variant base --dind-isolation 2>/dev/null) || EXIT=$?
rm -rf "$TMP_BIN"
check 8 "--dind-isolation with no Kata here warns of the privileged fallback" 1 "$EXIT" "$OUT" \
  "NOT AVAILABLE ON THIS MACHINE" "PLAIN, PRIVILEGED DinD sidecar" "--dind (privileged Docker-in-Docker sidecar)"

exit $FAILED
