#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# test-connection.sh - Test Azure CLI connection
#
# This script verifies that Azure credentials are properly configured
# by attempting to show the current account.
#
set -euo pipefail


echo "Checking Azure connection..."

if az account show >/dev/null 2>&1; then
  echo "✅ Azure connection OK"
  exit 0
else
  echo "❌ Azure connection FAILED"
  echo "Run 'az account show' manually for details."
  exit 1
fi
