#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Manual test: all 9 JetBrains IDEs with XFCE desktop
#
# This builds a booth with java:21, xfce, and all 9 JetBrains IDEs:
#   Community:  idea, pycharm
#   Commercial: goland, webstorm, phpstorm, clion, rider, rubymine, datagrip
#
# Expects ~5-9 GB of downloads. Run this when you have time and bandwidth.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

TEST_DIR="/tmp/test-jetbrains-all"
SELECT="java:21/xfce/idea/pycharm/goland/webstorm/phpstorm/clion/rider/rubymine/datagrip"

echo "═══════════════════════════════════════════════════════════"
echo "JetBrains All IDEs Manual Test"
echo "═══════════════════════════════════════════════════════════"
echo
echo "This will:"
echo "  1) codingbooth init  — generate Boothfile with all 9 JetBrains IDEs"
echo "  2) booth start       — build the Docker image (~5-9 GB of IDE downloads)"
echo
echo "Select: $SELECT"
echo "Target: $TEST_DIR"
echo
echo "Expected Boothfile order:"
echo "  40: setup xfce            (desktop infrastructure)"
echo "  50: setup jdk 21          (base language)"
echo "  60: setup jetbrains ...   (all 9 IDEs)"
echo

# --- Step 1: init ---
echo "── Step 1: codingbooth init ─────────────────────────────"
rm -rf "$TEST_DIR"
cli/codingbooth init new "$TEST_DIR" \
    --select "$SELECT" \
    --templates-path templates

echo
echo "Generated Boothfile:"
echo "---"
cat "$TEST_DIR/.booth/Boothfile"
echo "---"
echo

# --- Step 2: confirm before build ---
read -rp "Proceed with booth start (heavy build)? [y/N]: " CONFIRM
CONFIRM="$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')"
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
    echo "Stopped after init. Boothfile is at: $TEST_DIR/.booth/Boothfile"
    echo "To build later:  cd $TEST_DIR && booth start"
    exit 0
fi

# --- Step 3: build ---
echo
echo "── Step 2: booth start ──────────────────────────────────"
cd "$TEST_DIR"
"$ROOT_DIR/codingbooth"

echo
echo "═══════════════════════════════════════════════════════════"
echo "Done. The booth should be running."
echo "Connect via noVNC to verify IDEs are launchable."
echo
echo "Quick checks inside the booth:"
echo "  which idea pycharm goland webstorm phpstorm clion rider rubymine datagrip"
echo
echo "Cleanup:"
echo "  booth stop        # from $TEST_DIR"
echo "  rm -rf $TEST_DIR"
echo "═══════════════════════════════════════════════════════════"
