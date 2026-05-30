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

echo "=== STEP 5: shell-config landed in bashrc ==="
# The published wrapper may emit any of several historical marker formats.
# Just verify the function name appears in the rc file at all.
echo "BOOTH_REF: $(count 'booth' ~/.bashrc)"
BASH
)

# Pipe-install detection fired in the downloaded wrapper.
assert_contains "$LAST_OUTPUT" "Installing CodingBooth wrapper..."
# The downloaded wrapper successfully installed a binary.
assert_contains "$LAST_OUTPUT" "CodingBooth installed:"
# The wrapper's own success banner.
assert_contains "$LAST_OUTPUT" "CodingBooth has been installed"
# Wrapper file is on disk and executable.
assert_contains "$LAST_OUTPUT" "WRAPPER: OK"
# Lock file is present with a sane cache mode.
assert_contains "$LAST_OUTPUT" "version="
assert_contains "$LAST_OUTPUT" "cache="
# Wrapper runs and reports a version line.
assert_contains "$LAST_OUTPUT" "CodingBooth Wrapper:"
# shell-config succeeded and put a reference to booth into ~/.bashrc.
assert_contains "$LAST_OUTPUT" "Added booth function to"
# The grep for 'booth' returns ≥1 (don't pin the exact count — depends on
# which historical format the published wrapper writes).
assert_not_contains "$LAST_OUTPUT" "BOOTH_REF: 0"
pass
