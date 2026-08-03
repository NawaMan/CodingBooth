#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Run all complex tests
#
# Complex tests are tests that require custom Dockerfiles, setup scripts,
# and more elaborate configurations.
#
# Test discovery:
# - Looks for directories matching test-*/
# - Each directory should contain a script named test--<name>.sh
#   where <name> is the directory name without the "test-" prefix
#
# Usage:
#   ./run-complex-tests.sh                       # every test
#   ./run-complex-tests.sh test-boothfile-kafka  # only the named tests
#   ./run-complex-tests.sh --shard 2/4           # only shard 2 of 4
#   ./run-complex-tests.sh --list                # print the selection, run nothing
#   ./run-complex-tests.sh --no-retry            # fail on the first transient error
#
# Selection exists so CI can split the suite across jobs: a shard that fails can
# be re-run on its own instead of re-running all ~116 tests, which take ~23min.
# Shards are round-robin over the sorted test list, so they stay balanced and no
# per-test timing table has to be maintained.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---- args ----
SHARD_INDEX=0     # 1-based; 0 means "not sharded"
SHARD_TOTAL=0
LIST_ONLY=false
RETRY_TRANSIENT=true
SELECTED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shard)
      [[ "${2:-}" =~ ^([0-9]+)/([0-9]+)$ ]] || { echo "❌ --shard wants N/M (e.g. 2/4), got '${2:-}'" >&2; exit 2; }
      SHARD_INDEX="${BASH_REMATCH[1]}"; SHARD_TOTAL="${BASH_REMATCH[2]}"
      (( SHARD_TOTAL >= 1 && SHARD_INDEX >= 1 && SHARD_INDEX <= SHARD_TOTAL )) \
        || { echo "❌ --shard $2 is out of range" >&2; exit 2; }
      shift 2 ;;
    --list)     LIST_ONLY=true;       shift ;;
    --no-retry) RETRY_TRANSIENT=false; shift ;;
    -h|--help)  sed -n '6,28p' "$0"; exit 0 ;;
    -*)         echo "❌ unknown option '$1'" >&2; exit 2 ;;
    *)          SELECTED+=("${1%/}");  shift ;;
  esac
done

if [[ ${#SELECTED[@]} -gt 0 && "$SHARD_TOTAL" != "0" ]]; then
  echo "❌ --shard and explicit test names are mutually exclusive" >&2
  exit 2
fi

# ---- discovery ----
# Sorted, so shard membership is stable for a given commit — a re-run of shard 2
# runs exactly the tests shard 2 ran before.
ALL=()
for test_dir in test-*/; do ALL+=("${test_dir%/}"); done
IFS=$'\n' ALL=($(printf '%s\n' "${ALL[@]}" | sort)); unset IFS

TESTS=()
if [[ ${#SELECTED[@]} -gt 0 ]]; then
  for want in "${SELECTED[@]}"; do
    [[ -d "$want" ]] || { echo "❌ no such test directory: $want" >&2; exit 2; }
    TESTS+=("$want")
  done
elif [[ "$SHARD_TOTAL" != "0" ]]; then
  for i in "${!ALL[@]}"; do
    (( i % SHARD_TOTAL == SHARD_INDEX - 1 )) && TESTS+=("${ALL[$i]}")
  done
else
  TESTS=("${ALL[@]}")
fi

if [[ "$LIST_ONLY" == "true" ]]; then
  printf '%s\n' "${TESTS[@]}"
  exit 0
fi

LABEL="Running Complex Tests"
[[ "$SHARD_TOTAL" != "0" ]] && LABEL="${LABEL} — shard ${SHARD_INDEX}/${SHARD_TOTAL}"
echo "============================================================"
echo "$LABEL (${#TESTS[@]} of ${#ALL[@]})"
echo "============================================================"

# Record every booth invocation's command, exit code, and stderr for this suite.
# Complex tests discard booth's stderr (`2>/dev/null`), so when a run intermittently
# returns nothing the suite reports `FAILED:` with no output and nothing to go on.
# This is the trace that makes the next such failure explain itself.
# Opt out with CB_DIAG_LOG=/dev/null; point it elsewhere to relocate the log.
if [[ -z "${CB_DIAG_LOG:-}" ]]; then
  export CB_DIAG_LOG="${SCRIPT_DIR}/../logs/complex-booth-calls.log"
  mkdir -p "$(dirname "$CB_DIAG_LOG")"
  : >"$CB_DIAG_LOG"
  echo "Booth call trace: ${CB_DIAG_LOG}"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: Docker is not installed or not in PATH"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "SKIP: Docker daemon is not accessible (permission or not running)"
  exit 0
fi

# A complex test builds an image, so it fetches from github.com, PyPI, npm, apt …
# Every CI failure of this suite on record has been one of these rather than a
# real defect: an unauthenticated GitHub API budget exhausted mid-sweep (429), or
# the archive briefly unavailable (502/503). Retrying *only* on these signatures
# keeps a genuine failure failing on the first try, and the retry is reported so
# the flake stays visible instead of being silently absorbed.
TRANSIENT_RE='error: (429|50[0-9])|returned error: (429|50[0-9])|HTTP/[0-9.]+ (429|50[0-9])|[Rr]ate limit|Too Many Requests|Service Unavailable|Bad Gateway|Gateway Time-?out|Temporary failure in name resolution|Could not resolve host|Connection reset by peer|Connection timed out|TLS handshake timeout|i/o timeout|net/http: request canceled|Temporary failure resolving|Failed to fetch|Unable to connect to'

FAILED=0
PASSED=0
RETRIED=0
FAILED_TESTS=()
RETRIED_TESTS=()

# run-one <test-dir> <output-file> — stream the test live and capture it for the
# transient check. `pipefail` makes the pipeline carry the test's exit code.
run_one() {
  (cd "$1" && "./test--${1#test-}.sh") 2>&1 | tee "$2"
}

for test_dir in "${TESTS[@]}"; do
  test_script="test--${test_dir#test-}.sh"

  if [[ ! -x "${test_dir}/${test_script}" ]]; then
    echo ""
    echo "--- Skipping: ${test_dir} (no executable ${test_script}) ---"
    continue
  fi

  echo ""
  echo "--- Running: ${test_dir} ---"
  out="$(mktemp)"

  if run_one "$test_dir" "$out"; then
    echo "PASSED: ${test_dir}"
    PASSED=$((PASSED + 1))
  elif [[ "$RETRY_TRANSIENT" == "true" ]] && grep -qE "$TRANSIENT_RE" "$out"; then
    echo "⚠️  TRANSIENT network failure in ${test_dir} — retrying once"
    echo "    matched: $(grep -oE "$TRANSIENT_RE" "$out" | head -1)"
    RETRIED=$((RETRIED + 1))
    RETRIED_TESTS+=("${test_dir}")
    if run_one "$test_dir" "$out"; then
      echo "PASSED: ${test_dir} (after retry)"
      PASSED=$((PASSED + 1))
    else
      echo "FAILED: ${test_dir} (failed again after retry)"
      FAILED=$((FAILED + 1))
      FAILED_TESTS+=("${test_dir}")
    fi
  else
    echo "FAILED: ${test_dir}"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("${test_dir}")
  fi

  rm -f "$out"
done

echo ""
echo "============================================================"
TOTAL=$((PASSED + FAILED))
echo "Results: ${PASSED}/${TOTAL} passed"

# Surfaced even on a green run: a suite that only stays green by retrying is
# telling you something, and the count is the only place it shows.
if [ $RETRIED -gt 0 ]; then
  echo ""
  echo "⚠️  Retried after a transient network failure: ${RETRIED}"
  for test in "${RETRIED_TESTS[@]}"; do
    echo "  - $test"
  done
fi

if [ $FAILED -eq 0 ]; then
  echo "All complex tests passed!"
  exit 0
else
  echo ""
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  - $test"
  done
  echo ""
  echo "Re-run just these with:"
  echo "  ./run-complex-tests.sh ${FAILED_TESTS[*]}"
  exit 1
fi
