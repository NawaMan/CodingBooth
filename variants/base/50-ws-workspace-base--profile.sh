#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# 50-ws-workspace-base--profile.sh
# Container defaults (safe to source multiple times)

alias cp='cp -p'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias tree='tree -C'

# Environment Defaults
export EDITOR=${EDITOR:-tilde}
export TERM=${TERM:-xterm-256color}

# Permissions: default to 0664 files / 0775 dirs
umask 0002
