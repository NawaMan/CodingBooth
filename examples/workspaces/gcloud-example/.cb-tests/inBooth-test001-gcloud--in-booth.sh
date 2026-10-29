#!/bin/bash
set -euo pipefail
# gcloud CLI is installed and prints a version (no login)
echo "=== Testing gcloud ==="
command -v gcloud
gcloud --version | grep -q 'Google Cloud SDK'
