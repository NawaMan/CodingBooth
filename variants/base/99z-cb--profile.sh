#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# 99z-cb--profile.sh
# Main booth profile script with helper functions and welcome message.
# Sourced on interactive shell login.
# -----------------------------------------------------------------------------

# Only for interactive shells
case "$-" in
  *i*) ;;
  *) return ;;
esac


# Aliases
alias cp='cp -p'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias tree='tree -C'

# Environment Defaults
export EDITOR=${EDITOR:-tilde}
export TERM=${TERM:-xterm-256color}


# Welcome message
# Tip for those who are new to CodingBooth bash
if [ -z "${TIP_SHOWN:-}" ]; then
  export TIP_SHOWN=1
  echo "Welcome to CodingBooth!"
  echo ""
  echo "Your code is ready at ~/code"
  echo ""
  echo "Handy commands:"
  echo "  codingbooth-info   Show environment info"
  echo "  editor             Text editor (tilde)"
  echo "  explorer           File manager (mc)"
  echo ""
  echo "Want a different UI? Exit and rerun booth with --variant codeserver or --variant desktop-xfce"
  echo ""
  echo "AI Agent? Read /opt/codingbooth/AGENT.md or run: codingbooth-info"
  echo ""
fi
