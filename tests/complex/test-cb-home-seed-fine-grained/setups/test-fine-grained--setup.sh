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
#
# The -plain pair carries no .mount-this anywhere, so it is the subtree smart_copy
# takes in a single recursive cp rather than walking entry by entry. The walk and
# the bulk copy have to agree, so no-clobber, override and nesting are all asserted
# on this path too:
# - .testdir-plain/data.txt: exists during build — seed should NOT overwrite
# - .testdir-plain-override/nested/deep.txt: exists during build — override should overwrite
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

mkdir -p /home/coder/.testdir-plain
echo "ORIGINAL_PLAIN_FROM_BUILD" > /home/coder/.testdir-plain/data.txt
mkdir -p /home/coder/.testdir-plain-override/nested
echo "ORIGINAL_PLAIN_OVERRIDE_FROM_BUILD" > /home/coder/.testdir-plain-override/nested/deep.txt

chown -R coder:coder /home/coder/.testfile-individual /home/coder/.testdir /home/coder/.testfile-override /home/coder/.testdir-override /home/coder/.testdir-plain /home/coder/.testdir-plain-override 2>/dev/null || true

echo "Fine-grained copy test setup complete."
