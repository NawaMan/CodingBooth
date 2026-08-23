#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Silenced Build Progress Manual Test Runner
# Shows the one-line status a `--silence-build` build draws while it runs.
# This has to be run by hand: the line is only drawn to a terminal, so `go test`
# — which captures output — is precisely the case where it stays silent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "Silenced Build Progress Manual Test"
echo "═══════════════════════════════════════════════════════════"
echo
echo "This demo runs three silenced builds — one that goes quiet mid-step,"
echo "one that fails, and one with its stderr redirected to a file — so you"
echo "can see the transient status line appear, tick, and be erased."
echo
echo "It takes about a minute. Press Enter to start..."
read

cd "$SCRIPT_DIR/cli"
echo "Building test binary..."
go build -o /tmp/docker-build-progress-manual-test ./src/cmd/docker-build-progress-manual-test/main.go
cd "$SCRIPT_DIR"
/tmp/docker-build-progress-manual-test

# Part 3 — the case the test suites live in. Every complex test sends booth's
# stderr to /dev/null or to CB_DIAG_LOG and the suite pipes the test through
# `tee`, so stderr is never a terminal there. The line has to come from the
# controlling terminal instead, and the redirect has to stay clean.
echo
echo "───────────────────────────────────────────────────────────"
echo "Part 3 — the same build with stderr redirected to a file."
echo
echo "This is what a test does: 'codingbooth --silence-build ... 2>/dev/null'."
echo "You should STILL see the status line tick and vanish — it is drawn on the"
echo "terminal itself — and the redirected file must come back empty."
echo

REDIRECT_LOG=$(mktemp "${TMPDIR:-/tmp}/build-progress-redirect.XXXXXX")
/tmp/docker-build-progress-manual-test quiet 2>"$REDIRECT_LOG"

echo "✅ Part 3 done — the line above this one should be gone."
echo
if [[ -s "$REDIRECT_LOG" ]]; then
    echo "❌ The redirect caught output it should not have ($(wc -c <"$REDIRECT_LOG") bytes):"
    head -5 "$REDIRECT_LOG"
    rm -f "$REDIRECT_LOG"
    exit 1
fi
echo "✅ The redirected stderr is empty — nothing of the status line leaked into it."
rm -f "$REDIRECT_LOG"
