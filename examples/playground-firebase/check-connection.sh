#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# check-connection.sh — verify Firebase CLI sees a logged-in account.
#
set -euo pipefail

echo "Checking Firebase connection..."

if firebase login:list 2>&1 | grep -q "Logged in as"; then
  echo "✅ Firebase connection OK"
  firebase login:list 2>&1 | head -5
  exit 0
else
  echo "❌ Firebase connection FAILED"
  echo "Host needs: ~/.config/configstore/firebase-tools.json (run: firebase login)"
  echo "Inside booth, re-check mount and seed:"
  echo "  ls -la /etc/cb-home-seed/.config/configstore/"
  echo "  ls -la ~/.config/configstore/"
  firebase login:list 2>&1 || true
  exit 1
fi
