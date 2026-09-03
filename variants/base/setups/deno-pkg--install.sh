#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Deno packages for the 'coder' user.
# Packages are passed as a comma-separated list.
# It requires deno--setup.sh to have been run first.
# Usage: deno-pkg--install.sh <pkg1,pkg2,...>
# Examples:
#   deno-pkg--install.sh npm:cowsay
#   deno-pkg--install.sh npm:cowsay,npm:figlet

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
        echo "Usage: $0 <pkg1,pkg2,...>"
        echo "Examples:"
        echo "  $0 npm:cowsay"
        echo "  $0 npm:cowsay,npm:figlet"
        exit 0
        ;;
esac

# Split and trim the comma list up front, so an absent, empty or comma-only list
# is settled before the Deno probe.
IFS=',' read -ra RAW_PKGS <<< "${1:-}"
PKGS=()
for pkg in ${RAW_PKGS[@]+"${RAW_PKGS[@]}"}; do
    pkg=$(echo "$pkg" | xargs) # trim whitespace
    [ -n "$pkg" ] && PKGS+=("$pkg")
done

# No packages requested is a no-op, not an error: the deno pkg--extension emits
# `install deno-pkg ${DENO_PKGS}` with the list defaulting to empty, so failing
# here would break the image build of every project that selects it without
# naming packages.
if [ ${#PKGS[@]} -eq 0 ]; then
    echo "ℹ️  No Deno packages requested; nothing to install."
    exit 0
fi

if ! command -v deno &> /dev/null; then
    echo "❌ Deno is not installed. Run deno--setup.sh first." >&2
    exit 1
fi

for pkg in "${PKGS[@]}"; do
    echo "📦 Installing: deno add $pkg"
    cb_retry sudo -u coder bash -lc "cd /home/coder && deno add $pkg"
done
