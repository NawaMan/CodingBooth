#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Config (override via env or first arg)
# --------------------------
BREW_INSTALL_URL="${BREW_INSTALL_URL:-${1:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}}"
STARTUP_FILE="/usr/share/startup.d/57-ws-brew--startup.sh"
PROFILE_FILE="/etc/profile.d/57-ws-brew--profile.sh"


# ---- Create startup file: to be executed ----
cat >"${STARTUP_FILE}" <<"EOF"
#!/usr/bin/env bash
set -euo pipefail

# === Homebrew one-time bootstrap (idempotent) ================================

# If brew already exists, do nothing.
if command -v brew >/dev/null 2>&1; then
  exit 0
fi

# If running as root, skip (brew should be installed as non-root).
if [ "$(id -u)" = "0" ]; then
  echo "⚠️  Skipping Homebrew install: running as root. Install must run as a non-root user." >&2
  # Example: su -s /bin/bash <user> -c "$0"  (handled by your ENTRYPOINT if desired)
  exit 0
fi

# Helper: run command; if it fails, print its output.
run_quiet_or_dump() {
  set -o pipefail
  local out
  if ! out="$("$@" 2>&1)"; then
    printf '%s\n' "$out" >&2
    echo "❌ Command failed: $*" >&2
    return 1
  fi
}

# Minimal env for non-interactive install (no analytics, quiet env hints, etc.)
export NONINTERACTIVE="${NONINTERACTIVE:-1}"
export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
export HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED="${HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED:-1}"
: "${BREW_INSTALL_URL:=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"

echo "📦 Installing Homebrew (first-run bootstrap)..."

tmp="${TMPDIR:-/tmp}/brew-install.$$"
trap 'rm -f "$tmp"' EXIT

# Download installer script
if command -v curl >/dev/null 2>&1; then
  run_quiet_or_dump curl -fsSL --connect-timeout 10 --retry 3 --retry-delay 1 \
    -o "$tmp" "$BREW_INSTALL_URL"
elif command -v wget >/dev/null 2>&1; then
  run_quiet_or_dump wget -q --timeout=15 --tries=3 -O "$tmp" "$BREW_INSTALL_URL"
else
  echo "❌ Need curl or wget to install Homebrew." >&2
  exit 1
fi

# Run installer
run_quiet_or_dump bash "$tmp"

# Validate install locations we expect on Linux/macOS
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ] \
  || [ -x /opt/homebrew/bin/brew ] \
  || [ -x /usr/local/bin/brew ] \
  || command -v brew >/dev/null 2>&1; then
  echo "✅ Homebrew installed."
else
  echo "❌ Homebrew install finished but brew not found on disk." >&2
  exit 1
fi
EOF
chmod 755 "${STARTUP_FILE}"


# ---- Create profile script: to be source ----
cat >"$PROFILE_FILE" <<"EOF"
# /etc/profile.d/57-ws-brew--profile.sh
# Idempotent, safe to source multiple times. No installation here.

# Prefer non-interactive, quiet hints, and no analytics in shells too.
export NONINTERACTIVE="${NONINTERACTIVE:-1}"
export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
export HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED="${HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED:-1}"

# Load brew's shell environment (PATH, MANPATH, etc.) if available.
# Use a guard to avoid re-evaluating on every shell spawn.
if [ -z "${__WS_BREW_SHELLENV_DONE:-}" ]; then
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    __WS_BREW_SHELLENV_DONE=1
  elif [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    __WS_BREW_SHELLENV_DONE=1
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
    __WS_BREW_SHELLENV_DONE=1
  elif command -v brew >/dev/null 2>&1; then
    eval "$("$(command -v brew)" shellenv)"
    __WS_BREW_SHELLENV_DONE=1
  fi
  export __WS_BREW_SHELLENV_DONE
fi
EOF
chmod 644 "$PROFILE_FILE"

echo "✅ Brew installer ready. It will bootstrap on next login shell or \`source ${PROFILE_FILE}\` to use now."
