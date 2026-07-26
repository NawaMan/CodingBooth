#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
check() {
  local label="$1"
  shift
  if eval "$*"; then
    echo "  OK  $label"
  else
    echo "  FAIL $label"
    fail=1
  fi
}

echo "browser-shared-example layout"

check "config has shared-dirs" "grep -q 'shared-dirs' .booth/config.toml"
check "config has no cache-dirs" "! grep -q 'cache-dirs' .booth/config.toml"
check "config has no cache-files" "! grep -q 'cache-files' .booth/config.toml"
check "Default mount marker" "test -f .booth/shared/home/coder/.chrome-data/Default/.mount-this"
check "Extensions mount marker" "test -f .booth/shared/home/coder/.chrome-data/Default/Extensions/.mount-this"
check "Firefox mount marker" "test -f .booth/shared/home/coder/.mozilla/firefox/.mount-this"
check "Chrome Default gitignore sample" "test -f .booth/shared/home/coder/.chrome-data/Default/.gitignore"
check "Firefox gitignore sample" "test -f .booth/shared/home/coder/.mozilla/firefox/.gitignore"
check "Boothfile chrome policies" "grep -q chrome-managed-policies .booth/Boothfile"
check "Boothfile firefox policies" "grep -q firefox-managed-policies .booth/Boothfile"
check "docs sample chrome gitignore" "test -f ../../../docs/samples/browser-shared-chrome-Default.gitignore"
check "docs sample firefox gitignore" "test -f ../../../docs/samples/browser-shared-firefox.gitignore"

exit "$fail"
