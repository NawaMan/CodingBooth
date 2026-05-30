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


# ── Timer display + pending message notification (before each prompt) ──
_booth_timer_display() {
  # Only show prompt timers for terminal variant (COMMAND mode)
  # Other variants have timers in the web UI
  [[ "${BOOTH_RUNMODE:-}" == "COMMAND" ]] || return

  local now
  now=$(date +%s)

  # Print a blank line above the timers (only if at least one is shown)
  if [[ -n "${BOOTH_SHOW_RUN_TIME:-}" || -n "${BOOTH_SHOW_COUNT_DOWN:-}" ]]; then
    echo ""
  fi

  # Run time (count up, white)
  if [[ -n "${BOOTH_SHOW_RUN_TIME:-}" ]]; then
    local start_epoch
    if [[ "$BOOTH_SHOW_RUN_TIME" == "now" ]]; then
      # Capture the first invocation time
      if [[ -z "${_BOOTH_RUN_TIME_START:-}" ]]; then
        export _BOOTH_RUN_TIME_START="$now"
      fi
      start_epoch="$_BOOTH_RUN_TIME_START"
    else
      start_epoch="$BOOTH_SHOW_RUN_TIME"
    fi
    local elapsed=$(( now - start_epoch ))
    (( elapsed < 0 )) && elapsed=0
    local h=$(( elapsed / 3600 )) m=$(( (elapsed % 3600) / 60 )) s=$(( elapsed % 60 ))
    local fmt
    if (( h > 0 )); then
      printf -v fmt '%d:%02d:%02d' "$h" "$m" "$s"
    else
      printf -v fmt '%02d:%02d' "$m" "$s"
    fi
    printf '\033[2m[booth] ⏱ %s elapsed\033[0m\n' "$fmt"
  fi

  # Countdown (color-coded)
  if [[ -n "${BOOTH_SHOW_COUNT_DOWN:-}" ]]; then
    local remaining=$(( BOOTH_SHOW_COUNT_DOWN - now ))
    local color label
    if (( remaining <= 0 )); then
      color='\033[1;31m'  # red
      label="TIME'S UP"
    else
      local h=$(( remaining / 3600 )) m=$(( (remaining % 3600) / 60 )) s=$(( remaining % 60 ))
      if (( h > 0 )); then
        printf -v label '%d:%02d:%02d' "$h" "$m" "$s"
      else
        printf -v label '%02d:%02d' "$m" "$s"
      fi
      if (( remaining > 900 )); then
        color='\033[0;32m'    # dark green
      elif (( remaining > 600 )); then
        color='\033[1;33m'    # yellow
      elif (( remaining > 300 )); then
        color='\033[0;33m'    # orange (dark yellow)
      else
        color='\033[1;31m'    # red
      fi
      label="${label} remaining"
    fi
    printf "${color}[booth] ⏱ %s\033[0m\n" "$label"
  fi
}

_booth_msg_check() {
  _booth_timer_display

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
