#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: every network `curl` in variants/base/setups/ carries `--retry`
#
# The package managers needed cb_retry (tests/setups/test--install-retry.sh)
# because they have no retry of their own. curl does — `--retry` already covers
# 408, 429, 5xx and connection/timeout failures — so the gap there was simply that
# most call sites never passed it. One Microsoft Marketplace 503 had already failed
# five consecutive image builds; roughly a third of the catalog's downloads were
# one dropped connection from the same class of failure.
#
# Two rules are asserted, over every setup script:
#
#   1. Every real curl invocation carries `--retry`. Checked against the *logical*
#      command, following backslash continuations, because the flags often sit on
#      a later line than the word `curl`.
#
#   2. No curl is piped into a consumer that would be corrupted by a retry. A
#      retried transfer restarts from the beginning, so anything already reading
#      the stream sees the truncated first attempt followed by the whole body —
#      benign for `| sed` picking one match, but `| bash`, `| sh`, `| gpg` and
#      `| dd` all act on what they were fed. Those download to a file first.
#
# Purely static: it reads the scripts, runs none of them, and needs no image. Rule
# 1 is what keeps this honest over time — a newly added setup is covered the
# moment it lands, without editing this test.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"

ALL_PASSED=true
TEST_NUM=0

report() {  # report <ok> <desc> [detail-lines...]
    local ok="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        for line in "$@"; do echo "      $line"; done
        ALL_PASSED=false
    fi
}

# Scan once; the two rules read the result. A "real" invocation is `curl` followed
# by a flag, a URL or a variable — which excludes the many `apt-get install ... curl`
# package lists, `command -v curl` probes, and curl inside a comment.
SCAN=$(mktemp)
trap "rm -f $SCAN" EXIT

python3 - "$SETUPS_DIR" > "$SCAN" << 'SCANNER'
import glob, os, re, sys

setups = sys.argv[1]
REAL   = re.compile(r"""(^|[\s(`$])curl\s+([-'"$]|http)""")
PIPED  = re.compile(r"\|\s*(bash|sh|dd|gpg)\b|\|\s*env\b[^|]*\bsh\b|bash -c \"\$\(curl")

for path in sorted(glob.glob(os.path.join(setups, "*.sh"))
                 + glob.glob(os.path.join(setups, "libs", "*.sh"))):
    lines = open(path).read().split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip().startswith("#") or "curl" not in line or not REAL.search(line):
            i += 1
            continue
        # The logical command: follow backslash continuations.
        j = i
        while j < len(lines) and lines[j].rstrip().endswith("\\"):
            j += 1
        cmd = "\n".join(lines[i:j + 1])
        rel = os.path.relpath(path, setups)
        verdict = "RETRY" if "--retry" in cmd else "NO-RETRY"
        if PIPED.search(cmd):
            verdict += " PIPED"
        print(f"{verdict}\t{rel}:{i + 1}\t{lines[i].strip()[:90]}")
        i = j + 1
SCANNER

TOTAL=$(wc -l < "$SCAN" | tr -d ' ')

# Guard against the scanner silently matching nothing — an empty scan would make
# every rule below pass for the wrong reason.
if [ "$TOTAL" -ge 100 ]; then
    report true "the scanner found ${TOTAL} curl invocations across the catalog"
else
    report false "the scanner should find the catalog's curl invocations (found ${TOTAL}, expected 100+)" \
        "Has the scan regex or the setups layout changed?"
fi

# ---- Rule 1: every network curl carries --retry ----------------------------
MISSING=$(grep "^NO-RETRY" "$SCAN" | cut -f2,3 || true)
if [ -z "$MISSING" ]; then
    report true "all $(grep -c '^RETRY' "$SCAN") network curl calls carry --retry"
else
    mapfile -t MISSING_LINES <<< "$MISSING"
    report false "curl calls with no --retry: $(echo "$MISSING" | wc -l | tr -d ' ')" \
        "${MISSING_LINES[@]}" \
        "Add --retry: '--retry 5 --retry-delay 3 --retry-all-errors' for a plain" \
        "download, '--retry 3 --retry-delay 2' for a probe or a fallback chain" \
        "(no --retry-all-errors there, so a 404 still fails on the first call)."
fi

# ---- Rule 2: nothing retryable is piped into a consumer --------------------
PIPED=$(grep "PIPED" "$SCAN" | cut -f2,3 || true)
if [ -z "$PIPED" ]; then
    report true "no curl is piped into bash, sh, gpg or dd"
else
    mapfile -t PIPED_LINES <<< "$PIPED"
    report false "curl piped into a consumer a retry would corrupt: $(echo "$PIPED" | wc -l | tr -d ' ')" \
        "${PIPED_LINES[@]}" \
        "Download to a temp file with --retry first, then feed the file to the" \
        "consumer. A retried transfer restarts from the beginning, so a reader" \
        "of the stream gets the partial first attempt plus the whole body."
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
