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
export EDITOR=${EDITOR:-ttt}
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

# ── Session recording (booth --record) ──
# Every command typed at a prompt goes to the session's activity log when it
# starts (`cmd`), and its exit status and duration when it ends (`cmd-done`).
# bash and zsh only; see docs/BOOTH_RECORD.md for what this does not see.
if [ "${BOOTH_RECORD:-false}" = "true" ]; then
  _booth_record_dir="${BOOTH_RECORD_DIR:-$HOME/code/.booth/.tmp/record}"
  _booth_record_line() {
    local line
    line="$(date '+%Y-%m-%dT%H:%M:%S%z') ${BOOTH_CONTAINER_NAME:-booth} $*"
    line="${line//$'\n'/ }"
    printf '%s\n' "$line" >> "$_booth_record_dir/activity.log" 2>/dev/null
    return 0
  }
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    # In a string: bash must not have to parse zsh's array syntax.
    eval '
      _booth_record_preexec() {
        _booth_record_start=$SECONDS
        _booth_record_line cmd "shell=zsh" "pid=$$" "cwd=$PWD" "-- $1"
      }
      _booth_record_precmd() {
        local st=$?
        if [[ -n "${_booth_record_start:-}" ]]; then
          _booth_record_line cmd-done "pid=$$" "exit=$st" "secs=$(( SECONDS - _booth_record_start ))"
          unset _booth_record_start
        fi
        return $st
      }
      autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook preexec _booth_record_preexec
      # First, so that $? is still the command s status.
      precmd_functions=(_booth_record_precmd ${precmd_functions:#_booth_record_precmd})
    '
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    # PS0 is expanded after a command is read and before it runs — in a
    # subshell, so the start is passed to the prompt hook through a file.
    _booth_record_pre() {
      local cmd
      cmd="$(HISTTIMEFORMAT='' builtin history 1 | sed '1s/^ *[0-9]*\*\{0,1\} *//')"
      printf '%s\n' "$SECONDS" > "/tmp/.booth-record-cmd.$$" 2>/dev/null
      _booth_record_line cmd "shell=bash" "pid=$$" "cwd=$PWD" "-- $cmd"
    }
    _booth_record_post() {
      local st=$? start
      # `history 1` is how the command is read, so nothing may be kept out of
      # the history: no ignorespace, no HISTIGNORE.
      HISTCONTROL=ignoredups
      unset HISTIGNORE
      if [[ -f "/tmp/.booth-record-cmd.$$" ]]; then
        read -r start < "/tmp/.booth-record-cmd.$$"
        rm -f "/tmp/.booth-record-cmd.$$"
        _booth_record_line cmd-done "pid=$$" "exit=$st" "secs=$(( SECONDS - ${start:-$SECONDS} ))"
      fi
      return $st
    }
    # This file is sourced more than once per shell (see the welcome banner).
    # Taken out and put back first each time: the hook above prepends itself on
    # every pass, and $? must still be the command's when this one runs.
    PROMPT_COMMAND="${PROMPT_COMMAND//_booth_record_post;/}"
    PROMPT_COMMAND="_booth_record_post;${PROMPT_COMMAND:-}"
    case "${PS0:-}" in
      *_booth_record_pre*) ;;
      *) PS0='$(_booth_record_pre)'"${PS0:-}" ;;
    esac
  fi
  # booth-entry starts the recorder at boot; this covers a shell that beat it.
  ( booth--record ensure >/dev/null 2>&1 & )
  # Said in every new shell, and not silenced by --hide-welcome: a person must
  # be able to tell that what they do here is kept.
  if [ -z "${_cb_record_notice_shown:-}" ]; then
    _cb_record_notice_shown=1
    printf '\033[1;31m●\033[0m \033[1mThis booth session is recorded\033[0m: commands, terminal output, file changes and ports.\n'
    printf '  Run booth--record status for what is kept and where.\n\n'
  fi
fi

# Welcome message
# Tip for those who are new to CodingBooth bash.
# BOOTH_HIDE_WELCOME=true (booth --hide-welcome, hide-welcome = true in
# config.toml, or CB_HIDE_WELCOME=true) turns it off for the whole booth.
if [ "${BOOTH_HIDE_WELCOME:-false}" != "true" ] && [ -z "${_cb_welcome_shown:-}" ]; then
  # Deliberately NOT exported. ~/.bashrc re-sources /etc/profile.d/*-cb-*.sh
  # itself (for interactive shells that don't take the /etc/profile login
  # path), so a single logical session already sources this script twice —
  # a plain shell variable still dedupes that second pass within the same
  # process. Exporting it would do something worse than just surviving into
  # child processes: VS Code (and code-server) resolve what env vars your
  # shell profile sets by spawning a *hidden* probe — an interactive login
  # shell whose stdout is captured and parsed as JSON, never shown to any
  # user — and then seed every real terminal it opens afterward with that
  # captured environment. An exported guard gets swept into that snapshot and
  # pre-suppresses the banner in every real terminal the user actually opens.
  # A non-exported var never reaches the probe's `JSON.stringify(process.env)`
  # in the first place (that runs in a separate child process, which only
  # inherits exported vars), so it can't leak forward this way.
  _cb_welcome_shown=1
  # A Nerd Font glyph, shown only when one is actually installed (desktop
  # variants) — a quick, unannounced way to eyeball that the terminal's font
  # is really rendering Nerd Font glyphs, not just a tofu box.
  _cb_nerd_glyph=""
  [ -f /usr/share/fonts/truetype/fira-code-nerd-font/FiraCodeNerdFontMono-Regular.ttf ] && _cb_nerd_glyph=$' '
  echo "${_cb_nerd_glyph}Welcome to CodingBooth!"
  unset _cb_nerd_glyph
  echo ""
  echo "Your code is ready at ~/code"
  echo ""
  echo "Handy commands:"
  echo "  booth--info       Show environment info"
  echo "  booth--expose     Expose a container port to the host"
  echo "  booth--msg        View and respond to pending messages"
  echo "  booth--restart    Restart this booth (re-reads config)"
  echo "  booth--shutdown   Shut down this booth"
  echo "  editor            Text editor"
  echo "  explorer          File manager"
  echo "  just              Run recipes from a Justfile"
  echo ""
  echo "Want a different UI? Exit and rerun booth with --variant codeserver or --variant desktop-xfce"
  echo ""
  echo "AI Agent? Read /opt/codingbooth/AGENT.md"
  echo ""
fi
