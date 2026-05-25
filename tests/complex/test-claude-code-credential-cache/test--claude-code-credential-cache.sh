#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Claude Code credential + cache interaction
#
# Simulates the production scenario where:
# - .booth/cache/ persists ~/.claude/ (settings, projects, memory)
# - Host credentials are always fresh via /etc/cb-home/ override
#
# Test 1: Fresh host credentials overwrite stale cached credentials
# Test 2: Cached settings.json is preserved (not overwritten by host)
# Test 3: Cached projects/ directory is preserved
# Test 4: Host .claude.json is seeded when not in cache
# Test 5: Writing new settings inside container persists to cache
# Test 6: Re-run with updated host credentials picks up new credentials
# Test 7: Settings written in Test 5 survive the re-run
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Claude Code credential + cache interaction ==="

FAILED=0

# Setup: create .booth/cache with simulated cached state
mkdir -p .booth/cache/home/coder/.claude/projects
echo "" > .booth/cache/home/coder/.claude/.mount-this
echo '{"token":"STALE_CACHED_TOKEN"}' > .booth/cache/home/coder/.claude/.credentials.json
echo '{"permissions":{"allow":["Bash"]}}' > .booth/cache/home/coder/.claude/settings.json
echo 'CACHED_PROJECT_DATA' > .booth/cache/home/coder/.claude/projects/my-project.json

# Setup: host credential file the config.toml mounts as the override.
# host-credential/.claude.json is checked in; .claude/.credentials.json is
# rebuilt fresh per test run so Test 1 sees the expected token.
mkdir -p host-credential/.claude
echo '{"token":"FRESH_HOST_TOKEN_ABC123"}' > host-credential/.claude/.credentials.json

# Ensure .gitignore has cache/ entry (required by cache mount validation)
echo "cache/" >> .booth/.gitignore

# Cleanup on exit
cleanup() {
  rm -rf .booth/cache
  rm -rf host-credential/.claude
  # Remove the cache/ line we added to .gitignore.
  # Use a portable in-place sed (BSD/macOS requires an explicit suffix; GNU treats it as the expression).
  if sed --version >/dev/null 2>&1; then
    sed -i '/^cache\/$/d' .booth/.gitignore
  else
    sed -i '' '/^cache\/$/d' .booth/.gitignore
  fi
}
trap cleanup EXIT

# Test 1: Fresh host credentials overwrite stale cached credentials
ACTUAL=$(run_coding_booth -- cat /home/coder/.claude/.credentials.json 2>/dev/null | tr -d '\r\n')
EXPECTED='{"token":"FRESH_HOST_TOKEN_ABC123"}'

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" "host credentials overwrite stale cached credentials"
else
  print_test_result "false" "$0" "1" "host credentials should overwrite stale cached credentials"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: Cached settings.json is preserved
ACTUAL=$(run_coding_booth -- cat /home/coder/.claude/settings.json 2>/dev/null | tr -d '\r\n')
EXPECTED='{"permissions":{"allow":["Bash"]}}'

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "2" "cached settings.json preserved"
else
  print_test_result "false" "$0" "2" "cached settings.json should be preserved"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 3: Cached projects/ directory is preserved
ACTUAL=$(run_coding_booth -- cat /home/coder/.claude/projects/my-project.json 2>/dev/null | tr -d '\r\n')
EXPECTED="CACHED_PROJECT_DATA"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "3" "cached projects/ directory preserved"
else
  print_test_result "false" "$0" "3" "cached projects/ directory should be preserved"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 4: Host .claude.json is seeded (no-clobber — file doesn't exist in cache)
ACTUAL=$(run_coding_booth -- cat /home/coder/.claude.json 2>/dev/null | tr -d '\r\n')
EXPECTED='{"hasCompletedOnboarding":true,"theme":"dark"}'

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "4" "host .claude.json seeded into home"
else
  print_test_result "false" "$0" "4" "host .claude.json should be seeded into home"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 5: Writing new settings inside container persists to cache
run_coding_booth -- 'echo NEW_HISTORY_LINE > /home/coder/.claude/history.jsonl' 2>/dev/null
ACTUAL=$(cat .booth/cache/home/coder/.claude/history.jsonl | tr -d '\r\n')
EXPECTED="NEW_HISTORY_LINE"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "5" "new file written in container persists to cache"
else
  print_test_result "false" "$0" "5" "new file written in container should persist to cache"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 6: Update host credentials, re-run — picks up new credentials
echo '{"token":"REFRESHED_TOKEN_XYZ789"}' > host-credential/.claude/.credentials.json
ACTUAL=$(run_coding_booth -- cat /home/coder/.claude/.credentials.json 2>/dev/null | tr -d '\r\n')
EXPECTED='{"token":"REFRESHED_TOKEN_XYZ789"}'

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "6" "refreshed host credentials picked up on re-run"
else
  print_test_result "false" "$0" "6" "refreshed host credentials should be picked up"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Restore original host credential
echo '{"token":"FRESH_HOST_TOKEN_ABC123"}' > host-credential/.claude/.credentials.json

# Test 7: Settings written in Test 5 survive the re-run
ACTUAL=$(run_coding_booth -- cat /home/coder/.claude/history.jsonl 2>/dev/null | tr -d '\r\n')
EXPECTED="NEW_HISTORY_LINE"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "7" "cached settings survive credential refresh"
else
  print_test_result "false" "$0" "7" "cached settings should survive credential refresh"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
