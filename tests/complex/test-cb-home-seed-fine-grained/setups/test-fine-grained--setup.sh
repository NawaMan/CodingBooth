#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# test-fine-grained--setup.sh
#
# Creates files in /home/coder during build to test fine-grained copy behavior:
# - .testfile-individual: exists during build — seed should NOT overwrite (no-clobber)
# - .testdir/data.txt: exists during build — seed with .mount-this should NOT overwrite (no-clobber)
# - .testfile-override: exists during build — override should overwrite
# - .testdir-override/data.txt: exists during build — override with .mount-this should overwrite
# -----------------------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "Error on line $LINENO" >&2; exit 1' ERR

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Must run as root" >&2; exit 1; }

echo "Setting up fine-grained copy test..."

mkdir -p /home/coder/.testdir
echo "ORIGINAL_FROM_BUILD" > /home/coder/.testfile-individual
echo "ORIGINAL_DIR_FROM_BUILD" > /home/coder/.testdir/data.txt
echo "ORIGINAL_OVERRIDE_FROM_BUILD" > /home/coder/.testfile-override
mkdir -p /home/coder/.testdir-override
echo "ORIGINAL_OVERRIDE_DIR_FROM_BUILD" > /home/coder/.testdir-override/data.txt

chown -R coder:coder /home/coder/.testfile-individual /home/coder/.testdir /home/coder/.testfile-override /home/coder/.testdir-override 2>/dev/null || true

echo "Fine-grained copy test setup complete."
