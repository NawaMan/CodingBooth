#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# 99z-cb--startup.sh
# One-time startup script executed at first container start.
# Sets up shell aliases, environment defaults, git config, and umask.
# -----------------------------------------------------------------------------

set -euo pipefail

# Git aliases
git config --global alias.lg "log --oneline --graph --decorate --all"

# Permissions: default to 0664 files / 0775 dirs
umask 0002


