#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# docker-build.sh - Build and publish WorkSpace Docker images
#
# This script builds Docker images for all WorkSpace variants (base, notebook,
# codeserver, desktop-xfce, desktop-kde) using multi-architecture support.
# It can build locally or push to Docker Hub with cosign signature verification.
# Run with --help for usage information.
#
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
