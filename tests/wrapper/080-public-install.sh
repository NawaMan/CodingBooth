#!/usr/bin/env bash
# 080 — smoke test the published install flow at codingbooth.io.
#
# This test exercises what users actually do — `curl … install.sh | bash` —
# but it tests what is CURRENTLY PUBLISHED on the server, not the local
# wrapper. Skipped by default; opt in with:
#   tests/wrapper/run-all.sh --include-public
# (or just run this file directly).
PUBLIC=1
source "$(dirname "$0")/_lib.sh"
public_preflight

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
count() { local v; v=$(grep -cE "$1" "$2" 2>/dev/null) || v=0; echo "$v"; }

echo "=== STEP 1: curl | bash ==="
curl -fsSL https://codingbooth.io/install.sh | bash

echo "=== STEP 2: wrapper present and executable ==="
[[ -x ./booth ]] && echo "WRAPPER: OK" || echo "WRAPPER: MISSING"

echo "=== STEP 3: lock file ==="
if [[ -f .booth/tools/codingbooth.lock ]]; then
    cat .booth/tools/codingbooth.lock
else
    echo "LOCK: MISSING"
fi

echo "=== STEP 4: wrapper runs ==="
./booth version 2>&1 | head -10
BASH
)

# The installer ran to its own last line. This used to assert "Installing
# CodingBooth wrapper..." — the wrapper's pipe-install branch — but that branch
# is unreachable from this flow by design: install.sh fetches the wrapper with
# `curl -o` precisely so piping it does not delegate back here in a loop. The
# branch itself is real and still worth covering; it needs a test that pipes the
# *wrapper*, not the installer.
assert_contains "$LAST_OUTPUT" "Use ./booth from this project"
# The downloaded wrapper successfully installed a binary.
assert_contains "$LAST_OUTPUT" "CodingBooth installed:"
# install.sh's second step ran too, not just the download.
assert_contains "$LAST_OUTPUT" "Shell function installed"
# Wrapper file is on disk and executable.
assert_contains "$LAST_OUTPUT" "WRAPPER: OK"
# Lock file is present with a sane cache mode.
assert_contains "$LAST_OUTPUT" "version="
assert_contains "$LAST_OUTPUT" "cache="
# Wrapper runs and reports a version line.
assert_contains "$LAST_OUTPUT" "CodingBooth Wrapper:"
pass
