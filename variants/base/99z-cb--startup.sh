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

# Git aliases. Convenience only, so it must never abort startup: git may be
# absent, and even a --global write does repo discovery first -- which exits 128
# when the workspace .git is a dangling gitfile (worktree, submodule). Discovery
# walks upward, so run from / : the only cwd with no possible .git ancestor.
if command -v git > /dev/null 2>&1; then
  (cd / && git config --global alias.lg "log --oneline --graph --decorate --all") || true
fi

# Permissions: default to 0664 files / 0775 dirs
umask 0002


