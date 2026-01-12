#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# 100-ws--startup.sh
# One-time startup script executed at first container start.
# Sets up git aliases and other user configurations.

set -euo pipefail

git config --global alias.lg "log --oneline --graph --decorate --all"
