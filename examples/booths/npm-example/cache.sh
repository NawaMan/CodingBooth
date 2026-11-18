#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# The shared pnpm store, in one go: add a package to two fresh projects. pnpm is
# not in the image, so `npx pnpm` fetches it (through the shared npm cache). The
# first add downloads the package into booth-cache-pnpm; the second reuses it
# from there ("downloaded 0"), as it would in any other booth.
set -euo pipefail

PKG="${1:-left-pad}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for n in 1 2; do
  echo "--- project ${n}: pnpm add ${PKG}"
  mkdir -p "$WORK/p$n"
  (cd "$WORK/p$n" && npm init -y >/dev/null && npx --yes pnpm add "$PKG" 2>&1) \
    | grep -E "Progress:.*done|^\+ " || true
done
echo
echo "Project 2 shows \"downloaded 0\": ${PKG} came from the shared pnpm store."
echo "List the cache volumes from the host: docker volume ls --filter label=cb.volume=cache"
