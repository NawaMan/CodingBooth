#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# test-connection.sh - Test Google Cloud CLI connection
#
# This script verifies that gcloud credentials are properly configured
# by attempting to list authenticated accounts.
#
set -euo pipefail


echo "Checking gcloud connection..."

if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  echo "✅ gcloud connection OK"
  exit 0
else
  echo "❌ gcloud connection FAILED"
  echo "Run 'gcloud auth list' manually for details."
  exit 1
fi
