#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# test-connection.sh - Test Firebase CLI connection
#
# This script verifies that Firebase credentials are properly configured
# by attempting to list logged-in accounts.
#
set -euo pipefail


echo "Checking Firebase connection..."

if firebase login:list 2>&1 | grep -q "Logged in as"; then
  echo "✅ Firebase connection OK"
  exit 0
else
  echo "❌ Firebase connection FAILED"
  echo "Run 'firebase login:list' manually for details."
  exit 1
fi
