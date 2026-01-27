#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Colored Prompt Manual Test Runner
# This script tests that the web terminal (ttyd) shows a colored prompt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "Colored Prompt Manual Test (ttyd / Web Terminal)"
echo "═══════════════════════════════════════════════════════════"
echo
echo "This test verifies that the bash prompt has colors when"
echo "accessed via the web terminal (ttyd) at localhost:10000."
echo
echo "What to check:"
echo "  ✓ Prompt shows: containerName:~/code\$"
echo "  ✓ Container name should be GREEN"
echo "  ✓ Directory path should be BLUE"
echo
echo "What indicates FAILURE:"
echo "  ✗ Prompt shows: coder@hostname:~/code\$"
echo "  ✗ Everything is GREY (no colors)"
echo
echo "Press Enter to start booth..."
read

echo
echo "Starting booth (will open web terminal on port 10000)..."
echo "Once started, open http://localhost:10000 in your browser."
echo
echo "Press Ctrl+C when done testing."
echo "───────────────────────────────────────────────────────────"
echo

cd "$SCRIPT_DIR"
./coding-booth --variant base
