#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs global Bun packages for the 'coder' user.
# It requires bun--setup.sh to have been run first.
# Usage: bun--install.sh <package> [package...]

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

# No Bun packages requested is a no-op, not an error: the *-pkg templates emit
# `install bun ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No Bun packages requested; nothing to install."
    exit 0
fi

if ! command -v bun &> /dev/null; then
    echo "❌ Bun is not installed. Run bun--setup.sh first." >&2
    exit 1
fi

# Install global packages as coder user to avoid permission issues
cb_retry sudo -u coder bun add -g "$@"

# `bun add -g` drops command shims in ~/.bun/bin, which is not on PATH — the package
# installs "successfully" and the command is then not found. Expose them the same way
# every other install manager here does: symlink into /usr/local/bin.
BUN_BIN_DIR="$(sudo -u coder -H bash -lc 'echo "$HOME/.bun/bin"')"
if [ -d "$BUN_BIN_DIR" ]; then
    for f in "$BUN_BIN_DIR"/*; do
        [ -e "$f" ] || continue
        ln -sfn "$f" "/usr/local/bin/$(basename "$f")"
    done
fi
