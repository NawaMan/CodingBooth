#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# test-placeholder-seed.sh — prove empty / "{}" dest is replaced by host seed.
#
# Run inside the playground-firebase booth (after start), or:
#   codingbooth -- ./test-placeholder-seed.sh
#
set -euo pipefail

SEED="${CB_FIREBASE_SEED_FILE:-/etc/cb-home-seed/.config/configstore/firebase-tools.json}"
DEST_DIR="${HOME}/.config/configstore"
DEST="${DEST_DIR}/firebase-tools.json"
STARTUP="/usr/share/startup.d/60-cb-firebase--startup.sh"

echo "=== playground-firebase placeholder seed test ==="

if [[ ! -f "$SEED" ]]; then
  echo "❌ No host seed at $SEED"
  echo "   Mount firebase-tools.json via .booth/config.toml run-args."
  exit 1
fi
echo "• seed size: $(wc -c <"$SEED") bytes"

if [[ ! -x "$STARTUP" ]]; then
  echo "❌ Startup not installed: $STARTUP"
  echo "   Rebuild the booth image so setup firebase runs."
  exit 1
fi

mkdir -p "$DEST_DIR"
printf '%s\n' '{}' >"$DEST"
echo "• planted placeholder {} (size $(wc -c <"$DEST"))"

bash "$STARTUP"

if [[ ! -s "$DEST" ]]; then
  echo "❌ dest still empty after startup"
  exit 1
fi
content="$(tr -d '[:space:]' <"$DEST" || true)"
if [[ "$content" == "{}" ]]; then
  echo "❌ dest still placeholder {} after startup"
  exit 1
fi
echo "• dest after startup: $(wc -c <"$DEST") bytes"

if ! firebase login:list 2>&1 | grep -q "Logged in as"; then
  echo "❌ firebase login:list failed after seed"
  firebase login:list 2>&1 || true
  exit 1
fi

firebase login:list 2>&1 | head -5
echo "✅ placeholder seed test OK"
