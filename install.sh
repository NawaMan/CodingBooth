#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# CodingBooth Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/NawaMan/CodingBooth/main/install.sh | bash

set -euo pipefail

curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash
./booth install
./booth shell-config

# Detect current shell
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_NAME="zsh"
else
    SHELL_NAME="bash"
fi

echo ""
echo "To start using CodingBooth, restart your $SHELL_NAME session or run:"
echo ""
echo "  $SHELL_NAME"
echo ""
