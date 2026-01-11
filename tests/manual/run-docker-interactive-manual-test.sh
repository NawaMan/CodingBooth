#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Interactive Docker Manual Test Runner
# This script runs the standalone interactive manual test that supports real TTY

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "Docker Interactive Shell Manual Test"
echo "═══════════════════════════════════════════════════════════"
echo
echo "This demo will:"
echo "  • Detect if you're running in a real terminal"
echo "  • Show you the TTY status"
echo "  • Run docker with -it flags"
echo "  • Give you an interactive shell if TTY is available"
echo
echo "Press Enter to start..."
read

cd "$SCRIPT_DIR"
go run ./cli/src/cmd/docker-interactive-manual-test/main.go

