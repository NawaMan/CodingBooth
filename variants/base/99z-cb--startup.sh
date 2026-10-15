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

# Fresh (the default editor): the booth-lsp plugin starts the language servers
# that are on PATH and adds an "Install <server>" row to Fresh's LSP popup for a
# missing one. Fresh loads plugins only from the user's plugins directory, so
# link it in here, at container start, not in the profile: the profile runs for
# interactive shells only, and `booth -- fresh README.md` opens none. Anything
# already at that name, a link or a file of the user's own, is left alone; an
# empty file there turns the plugin off.
fresh_plugin="$HOME/.config/fresh/plugins/booth-lsp.ts"
if [[ ! -e "$fresh_plugin" && ! -L "$fresh_plugin" \
      && -r /opt/codingbooth/setups/fresh-plugins/booth-lsp.ts ]]; then
  { mkdir -p "${fresh_plugin%/*}" \
      && ln -s /opt/codingbooth/setups/fresh-plugins/booth-lsp.ts "$fresh_plugin"; } 2>/dev/null || true
fi
unset fresh_plugin

# Permissions: default to 0664 files / 0775 dirs
umask 0002


