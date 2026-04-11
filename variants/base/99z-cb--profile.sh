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


# ── booth command (walk up to find project booth wrapper) ──
if [[ -x "$HOME/code/booth" ]]; then
    eval "$("$HOME/code/booth" shell-config --eval 2>/dev/null)" 2>/dev/null || true
fi

# Aliases
alias cp='cp -p'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias tree='tree -C'

# Environment Defaults
export EDITOR=${EDITOR:-tilde}
export TERM=${TERM:-xterm-256color}


# ── Pending message notification (before each prompt) ──
_booth_msg_check() {
  local msg_dir="${HOME}/code/.booth/.tmp/messages"
  [[ -d "$msg_dir" ]] || return
  local count=0
  for f in "$msg_dir"/*.msg.json; do
    [[ -f "$f" ]] || continue
    local base_name="${f##*/}"
    local msg_id="${base_name%.msg.json}"
    [[ -f "$msg_dir/${msg_id}.response.json" ]] && continue
    count=$((count + 1))
  done
  if (( count > 0 )); then
    printf '\033[1;36m[booth] %d pending message(s) — run booth--msg to respond\033[0m\n' "$count"
  fi
}
# Install the hook for both bash and zsh
if [[ -n "${ZSH_VERSION:-}" ]]; then
  autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _booth_msg_check
elif [[ -n "${BASH_VERSION:-}" ]]; then
  PROMPT_COMMAND="_booth_msg_check${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi

# Welcome message
# Tip for those who are new to CodingBooth bash
if [ -z "${TIP_SHOWN:-}" ]; then
  export TIP_SHOWN=1
  echo "Welcome to CodingBooth!"
  echo ""
  echo "Your code is ready at ~/code"
  echo ""
  echo "Handy commands:"
  echo "  booth--info       Show environment info"
  echo "  booth--expose     Expose a container port to the host"
  echo "  booth--msg        View and respond to pending messages"
  echo "  booth--restart    Restart this booth (re-reads config)"
  echo "  booth--shutdown   Shut down this booth"
  echo "  editor            Text editor (tilde)"
  echo "  explorer          File manager (mc)"
  echo ""
  echo "Want a different UI? Exit and rerun booth with --variant codeserver or --variant desktop-xfce"
  echo ""
  echo "AI Agent? Read /opt/codingbooth/AGENT.md"
  echo ""
fi
