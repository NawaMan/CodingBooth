#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# OK when the AWS CLI can authenticate - here, from the AWS_* variables the
# aws-cli+env extension passed in from the host.
set -euo pipefail

echo "Checking AWS connection..."

if aws sts get-caller-identity >/dev/null 2>&1; then
  echo "✅ AWS connection OK"
  exit 0
else
  echo "❌ AWS connection FAILED"
  echo "Run 'aws sts get-caller-identity' manually for details."
  exit 1
fi
