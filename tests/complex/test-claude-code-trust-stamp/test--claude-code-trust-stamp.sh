#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Claude Code trust stamp
#
# Claude Code gates a folder behind "Quick safety check: Is this a project you
# created or one you trust?" before it will work in it. That gate is not a
# permission rule, so nothing in the Accept Edits allow list can suppress it: it
# is project state, recorded per path in ~/.claude.json. The settings cache
# persists ~/.claude/ — a directory — and .claude.json is a file beside it, so
# every start reseeds it from the host, whose copy has never heard of
# /home/coder/code. The booth's own "yes" was written and dropped at shutdown,
# so the prompt returned on every single start.
#
# The extension's startup segment stamps the flag, and steps aside when the file
# is a bind mount — cache/ or shared/ owns it there, and a persisted copy already
# carries the answer across restarts.
#
# Test 1: the code directory is stamped trusted
# Test 2: the stamp is idempotent — a second start leaves it trusted
# Test 3: the stamp steps aside when .claude.json is a cache mount
#
# The config is generated from the real template rather than checked in, so the
# test exercises what `booth config --select claude-code+auto-accept` actually
# emits. Runs only against a locally-rebuilt base image: the startup script is
# generated, but it needs a base whose booth-entry hands the seeded files to the
# booth user, which ships in the image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Claude Code trust stamp ==="

use_local_base_image || exit 0

FAILED=0

BOOTH_PATH=""
CHECK_DIR="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -f "$CHECK_DIR/codingbooth" && -x "$CHECK_DIR/codingbooth" ]]; then
        BOOTH_PATH="$CHECK_DIR/codingbooth"
        break
    fi
    CHECK_DIR="$(dirname "$CHECK_DIR")"
done
if [[ -z "$BOOTH_PATH" ]]; then
    echo "ERROR: Could not find codingbooth" >&2
    exit 1
fi
REPO_ROOT="$(dirname "$BOOTH_PATH")"

cleanup() { rm -rf "$SCRIPT_DIR/.booth"; }
trap cleanup EXIT

# Generate from the real template — the point is what booth config emits.
"$BOOTH_PATH" config "$SCRIPT_DIR" --no-tui --overwrite \
    --select "claude-code+auto-accept" \
    --templates-path "$REPO_ROOT/templates" >/dev/null 2>&1

# Test 1: the code directory is stamped trusted
ACTUAL=$(run_coding_booth -- 'jq -r ".projects[\"/home/coder/code\"].hasTrustDialogAccepted" ~/.claude.json' 2>/dev/null | tr -d '\r\n')

if [[ "$ACTUAL" == "true" ]]; then
  print_test_result "true" "$0" "1" "code directory stamped trusted"
else
  print_test_result "false" "$0" "1" "code directory should be stamped trusted"
  echo "  Expected: true"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: idempotent — the stamp is re-applied on every start, so a second run is
# still trusted even though the seeded .claude.json arrives fresh from the host.
ACTUAL=$(run_coding_booth -- 'jq -r ".projects[\"/home/coder/code\"].hasTrustDialogAccepted" ~/.claude.json' 2>/dev/null | tr -d '\r\n')

if [[ "$ACTUAL" == "true" ]]; then
  print_test_result "true" "$0" "2" "still trusted on a second start"
else
  print_test_result "false" "$0" "2" "should still be trusted on a second start"
  echo "  Expected: true"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 3: when .claude.json is a cache mount, the persisted copy owns the state and
# the stamp must not touch it. A sentinel that survives the run proves it stood down.
{
  echo ""
  echo 'cache-files = ["home/coder/.claude.json"]'
} >> .booth/config.toml
mkdir -p .booth/cache/home/coder
echo '{"cacheSentinel":true}' > .booth/cache/home/coder/.claude.json
echo "cache/" > .booth/.gitignore

run_coding_booth -- 'true' >/dev/null 2>&1
ACTUAL=$(cat .booth/cache/home/coder/.claude.json | tr -d '\r\n')
EXPECTED='{"cacheSentinel":true}'

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "3" "stamp steps aside when .claude.json is a cache mount"
else
  print_test_result "false" "$0" "3" "stamp should step aside when .claude.json is a cache mount"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
