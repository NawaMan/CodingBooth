#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# bismuth-gaps--setup.sh — deprecated: runs krohnkite-gaps--setup.sh (window gaps).
#
# Bismuth is a Plasma 5 KWin script; Ubuntu 26.04 ships Plasma 6, which dropped
# kwin-bismuth. Krohnkite is its Plasma 6 successor with the same keyboard
# model, so an existing Boothfile's `setup bismuth-gaps` keeps working and gets
# Krohnkite instead, with the same arguments. Commands and shortcuts are now
# start-krohnkite / stop-krohnkite.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "⚠️  bismuth-gaps--setup.sh is deprecated: Bismuth does not run on Plasma 6. Running krohnkite-gaps--setup.sh (Krohnkite, its Plasma 6 successor) instead." >&2
exec "$BASH" "$SCRIPT_DIR/krohnkite-gaps--setup.sh" "$@"
