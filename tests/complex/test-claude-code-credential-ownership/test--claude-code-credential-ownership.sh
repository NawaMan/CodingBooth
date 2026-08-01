#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: credential ownership inside a cache-mounted home directory
#
# The seed/override copies run as root, so every file they create is born
# root-owned. booth-entry's blanket ownership sweep uses `find -xdev`, which
# stops at the boundary of a cache/shared bind mount — so a credential copied
# into one (~/.claude/.credentials.json under .booth/cache/home/coder/.claude)
# kept root:root 0600 and the booth user got "Permission denied" reading its
# own credentials. The mount was present; the tool still could not authenticate.
#
# This is exactly the default claude-code shape: the credential extension writes
# into ~/.claude and the auto-selected settings-cache extension mounts it.
#
# The sibling test-claude-code-credential-cache does not catch this: it
# pre-creates the cached credential file on the host, and `cp` over an existing
# file keeps that file's owner.
#
# Test 1: overridden credential is readable by the booth user
# Test 2: overridden credential is owned by the booth user, not root
# Test 3: seeded credential is readable by the booth user
# Test 4: mode is preserved (0600 stays 0600 — ownership is fixed, not secrecy)
#
# Runs only against a locally-rebuilt base image (cb-local/codingbooth): the fix
# lives in booth-entry, which ships inside the base image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: credential ownership in a cache-mounted home directory ==="

use_local_base_image || exit 0

FAILED=0

# The cache mount stands in for the settings-cache extension. Deliberately leave
# the credential files OUT of it: the bug only shows when the copy has to create
# them, because creating is what makes them root-owned.
rm -rf .booth/cache
mkdir -p .booth/cache/home/coder/.claude
echo "" > .booth/cache/home/coder/.claude/.mount-this

# Booth refuses to start unless cache/ is gitignored. Written at run time rather
# than checked in: the repo's root .gitignore ignores nested .gitignore files, so
# a committed one would never reach a fresh clone and this test would fail there
# and only there. The sibling test-claude-code-credential-cache does the same.
echo "cache/" > .booth/.gitignore

# Host-side credentials, 0600 as real ones are.
mkdir -p host-credential/.claude
echo '{"token":"OVERRIDE_TOKEN"}' > host-credential/.claude/.credentials.json
echo '{"token":"SEEDED_TOKEN"}'   > host-credential/.claude/seeded-secret.json
chmod 600 host-credential/.claude/.credentials.json host-credential/.claude/seeded-secret.json

cleanup() {
  rm -rf .booth/cache
  rm -f .booth/.gitignore
  rm -f host-credential/.claude/.credentials.json host-credential/.claude/seeded-secret.json
}
trap cleanup EXIT

# One booth run collects everything: reading as the booth user is the actual
# assertion, so each value is produced by the same unprivileged shell that a
# real `claude` invocation would run under.
REPORT=$(run_coding_booth -- '
  cat /home/coder/.claude/.credentials.json 2>/dev/null || echo UNREADABLE
  stat -c %U /home/coder/.claude/.credentials.json
  cat /home/coder/.claude/seeded-secret.json 2>/dev/null || echo UNREADABLE
  stat -c %a /home/coder/.claude/.credentials.json
' 2>/dev/null | tr -d '\r')

OVERRIDE_BODY=$(echo "$REPORT" | sed -n '1p')
OVERRIDE_OWNER=$(echo "$REPORT" | sed -n '2p')
SEEDED_BODY=$(echo "$REPORT" | sed -n '3p')
OVERRIDE_MODE=$(echo "$REPORT" | sed -n '4p')

# Test 1: overridden credential is readable by the booth user
EXPECTED='{"token":"OVERRIDE_TOKEN"}'
if [[ "$OVERRIDE_BODY" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" "overridden credential readable by the booth user"
else
  print_test_result "false" "$0" "1" "overridden credential should be readable by the booth user"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $OVERRIDE_BODY"
  FAILED=$((FAILED + 1))
fi

# Test 2: overridden credential is owned by the booth user, not root
if [[ "$OVERRIDE_OWNER" == "coder" ]]; then
  print_test_result "true" "$0" "2" "overridden credential owned by the booth user"
else
  print_test_result "false" "$0" "2" "overridden credential should be owned by the booth user"
  echo "  Expected: coder"
  echo "  Actual:   $OVERRIDE_OWNER"
  FAILED=$((FAILED + 1))
fi

# Test 3: seeded credential is readable by the booth user
EXPECTED='{"token":"SEEDED_TOKEN"}'
if [[ "$SEEDED_BODY" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "3" "seeded credential readable by the booth user"
else
  print_test_result "false" "$0" "3" "seeded credential should be readable by the booth user"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $SEEDED_BODY"
  FAILED=$((FAILED + 1))
fi

# Test 4: the fix hands over ownership without widening the mode
if [[ "$OVERRIDE_MODE" == "600" ]]; then
  print_test_result "true" "$0" "4" "credential mode stays 0600"
else
  print_test_result "false" "$0" "4" "credential mode should stay 0600"
  echo "  Expected: 600"
  echo "  Actual:   $OVERRIDE_MODE"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
