#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Manual Test: --sudo flag and no-sudo template
# Tests sudo access control in booth containers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "--sudo flag & no-sudo template — Manual Test Checklist"
echo "═══════════════════════════════════════════════════════════"
echo
echo "All commands should be run from a project directory with .booth/"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Part 1: Runtime flag (--sudo)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  1. Default (sudo enabled)"
echo "     Run:    booth -- bash -lc 'sudo whoami'"
echo "     Expect: root"
echo
echo "  2. --sudo true (explicit enable)"
echo "     Run:    booth --sudo true -- bash -lc 'sudo whoami'"
echo "     Expect: root"
echo
echo "  3. --sudo false (disable sudo)"
echo "     Run:    booth --sudo false -- bash -lc 'sudo whoami'"
echo "     Expect: Permission denied or 'coder is not in the sudoers file'"
echo
echo "  4. --no-sudo shorthand"
echo "     Run:    booth --no-sudo -- bash -lc 'sudo whoami'"
echo "     Expect: Permission denied or 'coder is not in the sudoers file'"
echo
echo "  5. --sudo false — verify setup scripts still worked"
echo "     Run:    booth --sudo false -- bash -lc 'which git && which curl'"
echo "     Expect: Both found (setup scripts ran with sudo before revocation)"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Part 2: config.toml (project-level default)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  Setup: Add 'sudo = false' to .booth/config.toml"
echo
echo "  6. config.toml sudo=false"
echo "     Run:    booth -- bash -lc 'sudo whoami'"
echo "     Expect: Permission denied (config.toml disables sudo)"
echo
echo "  7. config.toml sudo=false + --sudo true (runtime override)"
echo "     Run:    booth --sudo true -- bash -lc 'sudo whoami'"
echo "     Expect: root (runtime flag overrides config.toml)"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Part 3: no-sudo template"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  8. Init with no-sudo template"
echo "     Run:    booth config --no-tui /tmp/test-no-sudo --select 'go/no-sudo'"
echo "     Check:  cat /tmp/test-no-sudo/.booth/config.toml"
echo "     Expect: Contains 'sudo = false'"
echo
echo "  9. Run the project initialized with no-sudo"
echo "     Run:    cd /tmp/test-no-sudo && booth -- bash -lc 'sudo whoami'"
echo "     Expect: Permission denied"
echo
echo "  10. Override no-sudo template at runtime"
echo "      Run:    cd /tmp/test-no-sudo && booth --sudo true -- bash -lc 'sudo whoami'"
echo "      Expect: root"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Part 4: Interactive session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  11. Keep-alive with --no-sudo"
echo "      Run:    booth --no-sudo --keep-alive --name sudo-test"
echo "      Shell:  booth shell sudo-test"
echo "      Inside: Try 'sudo apt update'"
echo "      Expect: Permission denied"
echo "      Cleanup: booth stop sudo-test && booth remove sudo-test"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cleanup:"
echo "  rm -rf /tmp/test-no-sudo"
echo
