#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

# This script installs global .NET tools for the booth user ('coder' unless CB_USER_NAME says otherwise).
# It requires dotnet--setup.sh to have been run first.
# Usage: dotnet--install.sh <tool[@version]> [tool[@version]...]
# Example: dotnet--install.sh dotnet-ef
#          dotnet--install.sh dotnet-ef@8.0.11
#          dotnet--install.sh csharpier,dotnet-ef
#
# A trailing @version pins the tool (translated to `dotnet tool install --version`).
# Tools land in ~/.dotnet/tools, which the dotnet profile puts on PATH.

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
        echo "Usage: $0 <tool[@version]> [tool[@version]...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No dotnet tools requested is a no-op, not an error: the *-pkg templates emit
# `install dotnet ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No dotnet tools requested; nothing to install."
    exit 0
fi

DOTNET_ROOT="${DOTNET_ROOT:-/opt/dotnet-stable}"
DOTNET_BIN="${DOTNET_BIN:-$DOTNET_ROOT/dotnet}"

if [ ! -x "$DOTNET_BIN" ]; then
    echo "❌ .NET SDK is not installed. Run dotnet--setup.sh first." >&2
    exit 1
fi

# Install each tool as the booth user (coder unless CB_USER_NAME says otherwise) so shims go to its ~/.dotnet/tools.
CB_USER_NAME="${CB_USER_NAME:-coder}"
CB_USER_HOME="${CB_USER_HOME:-$(getent passwd "$CB_USER_NAME" 2>/dev/null | cut -d: -f6 || true)}"
CB_USER_HOME="${CB_USER_HOME:-/home/${CB_USER_NAME}}"
for spec in "$@"; do
    tool="${spec%@*}"
    if [ "$tool" = "$spec" ]; then
        echo "📦 Installing .NET tool: $tool"
        cb_retry sudo -u "$CB_USER_NAME" env \
            DOTNET_ROOT="$DOTNET_ROOT" \
            DOTNET_CLI_TELEMETRY_OPTOUT=1 \
            DOTNET_NOLOGO=1 \
            PATH="$DOTNET_ROOT:$CB_USER_HOME/.dotnet/tools:$PATH" \
            HOME="$CB_USER_HOME" \
            "$DOTNET_BIN" tool install --global "$tool"
    else
        version="${spec##*@}"
        echo "📦 Installing .NET tool: $tool (version $version)"
        cb_retry sudo -u "$CB_USER_NAME" env \
            DOTNET_ROOT="$DOTNET_ROOT" \
            DOTNET_CLI_TELEMETRY_OPTOUT=1 \
            DOTNET_NOLOGO=1 \
            PATH="$DOTNET_ROOT:$CB_USER_HOME/.dotnet/tools:$PATH" \
            HOME="$CB_USER_HOME" \
            "$DOTNET_BIN" tool install --global "$tool" --version "$version"
    fi
done

echo "✅ .NET tools installed."
for spec in "$@"; do
    tool="${spec%@*}"
    echo -n "   $tool → "
    sudo -u "$CB_USER_NAME" env \
        PATH="$CB_USER_HOME/.dotnet/tools:$DOTNET_ROOT:$PATH" \
        HOME="$CB_USER_HOME" \
        bash -lc "command -v '$tool' 2>/dev/null || command -v \"\${tool#dotnet-}\" 2>/dev/null || echo '(tool shim may use a different command name)'"
done
