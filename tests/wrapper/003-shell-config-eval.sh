#!/usr/bin/env bash
# 003 — ./booth shell-config --eval prints the one-line booth() function
#       with the v5 marker (no install, no network).
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth shell-config --eval
BASH
)

# Should be a single line, contain booth(), the install URL, and the marker.
assert_contains "$LAST_OUTPUT" "booth()"
assert_contains "$LAST_OUTPUT" "codingbooth.io/install.sh"
assert_contains "$LAST_OUTPUT" "# booth function v6"

# Sanity: eval the output and call the function — it should fail with
# return 127 because /work has no booth wrapper at this point.
LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth /tmp/booth-source
eval "$(/tmp/booth-source shell-config --eval)"
set +e
booth help >/dev/null 2>&1
echo "exit=$?"
BASH
)
assert_contains "$LAST_OUTPUT" "exit=127"
pass
