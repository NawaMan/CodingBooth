#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# 99z-cb--profile.sh
# Main booth profile script with helper functions and welcome message.
# Sourced on interactive shell login.

# Only for interactive shells
case "$-" in
  *i*) ;;
  *) return ;;
esac

JPERM_INSTALLED=false
# nbook: Terminal-based notebook using jpterm (lazy installed on first run)
function nbook() {
  if [ "$JPERM_INSTALLED" = false ]; then

    echo "First run: Installing jpterm (Jupyter Terminal) -- this can take a while ..."

    LOG_FILE="/var/setup.log"
    sudo mkdir -p /var
    sudo touch /var/setup.log
    sudo chmod 777 /var/setup.log

    run_quiet() {
      "$@" >>"$LOG_FILE" 2>&1
      local status=$?

      if [ $status -ne 0 ]; then
        echo "❌ ERROR: command failed: $*" >&2
        echo "----- LOG OUTPUT ($LOG_FILE) -----" >&2
        cat "$LOG_FILE" >&2 || echo "(log file not found)" >&2
        echo "---------------------------------" >&2
        on_error "$*" "$status"
        exit $status
      fi
    }

    on_error() {
      local cmd="$1"
      local code="$2"

      # --- your error hook here ---
      # Examples:
      # logger -t setup "Command failed ($code): $cmd"
      # mail -s "Setup failed" admin@example.com < "$LOG_FILE"
      # curl -X POST https://hooks.slack.com/... -d "Setup failed"

      echo "Hook: $cmd failed with exit code $code" >>"$LOG_FILE"
    }

    # export PATH="$HOME/.local/bin:$PATH"


    run_quiet python3 -m pip install pipx
    run_quiet pipx ensurepath

    run_quiet pipx install jpterm
    run_quiet python3 -m pip install --no-cache-dir jupyter_client bash_kernel
    run_quiet python3 -m bash_kernel.install

    JPERM_INSTALLED=true
  fi

  echo "Opening nbook..."
  echo -e "After you quit jpterm, it can stuck in the background, you may have to do \e[1;34mCtrl+C\e[0m."
  jpterm "$@"
}

# notebook: Smart launcher - uses start-notebook (JupyterLab) if available, otherwise nbook (jpterm)
function notebook() {
  local mode=""
  local args=()
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode=*)
        mode="${1#--mode=}"
        shift
        ;;
      --mode)
        mode="$2"
        shift 2
        ;;
      --help|-h)
        echo "notebook - Smart notebook launcher"
        echo ""
        echo "Usage: notebook [--mode=MODE] [OPTIONS...]"
        echo ""
        echo "Modes:"
        echo "  server    Run JupyterLab in browser (requires notebook--setup.sh)"
        echo "  cli       Run jpterm in terminal (lazy installed)"
        echo "  auto      Auto-select based on availability (default)"
        echo ""
        echo "If no mode is specified, uses 'server' if start-notebook is available,"
        echo "otherwise falls back to 'cli' (jpterm)."
        echo ""
        echo "Examples:"
        echo "  notebook                  # Auto-select"
        echo "  notebook --mode=server    # Force JupyterLab"
        echo "  notebook --mode=cli       # Force jpterm"
        return 0
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  
  # Determine which to run
  case "$mode" in
    server)
      if command -v start-notebook &>/dev/null; then
        start-notebook "${args[@]}"
      else
        echo "❌ start-notebook not available. Run notebook--setup.sh first or use --mode=cli"
        return 1
      fi
      ;;
    cli)
      nbook "${args[@]}"
      ;;
    auto|"")
      if command -v start-notebook &>/dev/null; then
        start-notebook "${args[@]}"
      else
        nbook "${args[@]}"
      fi
      ;;
    *)
      echo "❌ Unknown mode: $mode (use 'server', 'cli', or 'auto')"
      return 1
      ;;
  esac
}

# Only once per login session
if [ -z "${TIP_SHOWN:-}" ]; then
  export TIP_SHOWN=1
  echo "Welcome to the CodingBooth!"
  echo ""
  echo "Tip: use 'editor'   or 'tilde' to open the terminal text editor."
  echo "Tip: use 'explorer' or 'mc'    to open the terminal file manager."
  echo "Tip: use 'notebook'            to open the notebook (jpterm or jupyterlab)."
  echo ""
  echo "Looking for different UIs? Exit and rerun with --variant <variant-name> or consult help for more info."
  echo ""
fi
