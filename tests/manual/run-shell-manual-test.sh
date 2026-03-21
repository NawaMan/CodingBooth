#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Manual Test: booth shell
# This test requires an interactive TTY and cannot be automated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "booth shell — Manual Test Checklist"
echo "═══════════════════════════════════════════════════════════"
echo
echo "Prerequisites:"
echo "  Start a keep-alive booth in another terminal:"
echo "    booth --variant terminal --keep-alive --name shell-test"
echo
echo "Test checklist:"
echo
echo "  1. Basic shell"
echo "     Run:    booth shell shell-test"
echo "     Expect: Interactive bash session as 'coder' in /home/coder/code"
echo "     Check:  whoami => coder, pwd => /home/coder/code"
echo "     Exit:   Ctrl+D (booth should keep running)"
echo
echo "  2. Specific shell"
echo "     Run:    booth shell shell-test --shell zsh"
echo "     Expect: zsh session (check with: echo \$SHELL or ps -p \$\$)"
echo
echo "  3. Custom starting directory"
echo "     Run:    booth shell shell-test --dir /tmp"
echo "     Expect: pwd => /tmp"
echo
echo "  4. Environment variable via -e"
echo "     Run:    booth shell shell-test -e MY_VAR=hello"
echo "     Expect: echo \$MY_VAR => hello"
echo
echo "  5. Environment file via --envfile"
echo "     Prep:   echo 'FILE_VAR=world' > /tmp/test.env"
echo "     Run:    booth shell shell-test --envfile /tmp/test.env"
echo "     Expect: echo \$FILE_VAR => world"
echo
echo "  6. Session isolation"
echo "     Open two shells: booth shell shell-test (twice)"
echo "     Expect: Both sessions work independently"
echo "     Exit one: the other should remain active"
echo
echo "Cleanup:"
echo "  booth stop shell-test"
echo "  booth remove shell-test"
echo
