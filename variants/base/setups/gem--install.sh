#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Ruby gems for the 'coder' user.
# It requires ruby--setup.sh to have been run first.
# Usage: gem--install.sh <gem> [gem...]
# Example: gem--install.sh rails bundler pry

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
        echo "Usage: $0 <gem> [gem...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No gems requested is a no-op, not an error: the *-pkg templates emit
# `install gem ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No gems requested; nothing to install."
    exit 0
fi

if [ ! -x /opt/rbenv/shims/gem ]; then
    echo "❌ Ruby is not installed. Run ruby--setup.sh first." >&2
    exit 1
fi

# Install gems as coder user so they go to coder's ~/.gem
for gem_name in "$@"; do
    echo "💎 Installing $gem_name..."
    cb_retry sudo -u coder bash -lc "gem install '$gem_name' --no-document"
done
