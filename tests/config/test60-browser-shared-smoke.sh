#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Smoke: browser shared extensions emit shared-dirs only (never cache-dirs),
# and managed-policies extensions emit setup lines in the Boothfile.

source "$(dirname "$0")/test-helpers--source.sh"

begin

run rm -Rf "$prj" ; mkdir -p "$prj"
run booth config "$prj" --no-tui --select \
  "google-chrome+bookmarks-shared+settings-shared+extensions-shared+managed-policies/firefox+bookmarks-shared+settings-shared+extensions-shared+managed-policies/chromium+extensions-shared+managed-policies"

# Helper for file-exists assertions (same pattern as test59)
assert_file() {
  local path="$1"
  local label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  local pad
  pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
  echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
  if [ -f "$path" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $path to exist"
  fi
}

assert_file "$prj/.booth/shared/home/coder/.chrome-data/Default/.mount-this" \
  "chrome Default shared marker"
assert_file "$prj/.booth/shared/home/coder/.chrome-data/Default/Extensions/.mount-this" \
  "chrome Extensions shared marker"
assert_file "$prj/.booth/shared/home/coder/.mozilla/firefox/.mount-this" \
  "firefox shared marker"

# config must declare shared-dirs
TEST_COUNT=$((TEST_COUNT + 1))
if grep -q 'shared-dirs' "$prj/.booth/config.toml"; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: config lists shared-dirs ......................... \033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: config lists shared-dirs")
  echo -e "Test ${TEST_COUNT}: config lists shared-dirs ......................... \033[31mFAILED\033[0m"
fi

TEST_COUNT=$((TEST_COUNT + 1))
if grep -E 'cache-(dirs|files)' "$prj/.booth/config.toml" 2>/dev/null | grep -qE 'chrome-data|mozilla'; then
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: no browser paths in cache-*")
  echo -e "Test ${TEST_COUNT}: no browser paths in cache-* .................... \033[31mFAILED\033[0m"
else
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: no browser paths in cache-* .................... \033[32mPASSED\033[0m"
fi

TEST_COUNT=$((TEST_COUNT + 1))
if grep -q 'setup chrome-managed-policies' "$prj/.booth/Boothfile"; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: Boothfile has chrome-managed-policies ............. \033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: Boothfile has chrome-managed-policies")
  echo -e "Test ${TEST_COUNT}: Boothfile has chrome-managed-policies ............. \033[31mFAILED\033[0m"
fi

TEST_COUNT=$((TEST_COUNT + 1))
if grep -q 'setup firefox-managed-policies' "$prj/.booth/Boothfile"; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: Boothfile has firefox-managed-policies ............ \033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: Boothfile has firefox-managed-policies")
  echo -e "Test ${TEST_COUNT}: Boothfile has firefox-managed-policies ............ \033[31mFAILED\033[0m"
fi

# cache tree for browser paths must not be created
TEST_COUNT=$((TEST_COUNT + 1))
if [ -d "$prj/.booth/cache/home/coder/.chrome-data" ] || [ -d "$prj/.booth/cache/home/coder/.mozilla" ]; then
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: no .booth/cache browser dirs")
  echo -e "Test ${TEST_COUNT}: no .booth/cache browser dirs .................... \033[31mFAILED\033[0m"
else
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: no .booth/cache browser dirs .................... \033[32mPASSED\033[0m"
fi

finally
