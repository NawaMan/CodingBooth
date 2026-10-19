#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# The shared download cache, in one go: install a package that is not baked
# into the image twice, each time into a fresh --target (coder cannot write the
# image environment). The first download fills booth-cache-pip; the second
# install is served from it ("Using cached"), as it would be in any other booth.
set -euo pipefail

PKG="${1:-six}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "=== pip cache: ${PIP_CACHE_DIR:-<default>} ==="
for n in 1 2; do
  echo "--- install ${n}: pip install --target <tmp> ${PKG}"
  pip install --target "$WORK/t$n" "$PKG" 2>&1 | grep -E "Using cached|Downloading|Collecting|Successfully" || true
done
echo
echo "The second install printed \"Using cached\": it came from the shared volume."
echo "List the cache volumes from the host: docker volume ls --filter label=cb.volume=cache"
