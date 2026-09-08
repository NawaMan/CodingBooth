#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Homebrew packages for the 'coder' user.
# It will install Homebrew if it is not already installed (276MB).
# Usage: brew--install.sh <package> [package...]

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# cb_retry retries the network-bound install below past a transient registry
# error (a 5xx, a dropped connection) and nothing else, so a bad package name
# still fails on the first attempt. The lib sits beside this script both in the
# image (/opt/codingbooth/setups/) and in the repo, so a host-run test finds it.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <package> [package...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No Homebrew packages requested is a no-op, not an error: the *-pkg templates emit
# `install brew ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No Homebrew packages requested; nothing to install."
    exit 0
fi

BREW_PREFIX="${LINUXBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"
BREW_BIN="${BREW_PREFIX}/bin/brew"

if [ ! -x "$BREW_BIN" ]; then
    echo "brew is not installed."
    /opt/codingbooth/setups/brew--install.sh
fi

# Linuxbrew often exits 1 after a successful install because a formula
# "provides a service which can only be used on macOS or systemd" or
# because a binary is shadowed by /usr/sbin (nginx). That is a warning,
# not a missing package — treating it as fatal failed homebrew-example.
if ! cb_retry sudo -u coder "$BREW_BIN" install "$@"; then
    missing=()
    for pkg in "$@"; do
        if ! sudo -u coder "$BREW_BIN" list --formula "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo "❌ brew install failed and these packages are missing: ${missing[*]}" >&2
        exit 1
    fi
    echo "⚠️  brew install exited non-zero, but all requested packages are present."
fi
chown -R root:linuxbrew /home/linuxbrew
chmod -R g+w /home/linuxbrew
