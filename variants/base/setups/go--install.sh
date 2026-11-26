#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.2.0

# This script installs Go packages for the booth user ('coder' unless CB_USER_NAME says otherwise).
# It requires go--setup.sh to have been run first.
# Usage: go--install.sh <package@version> [package@version...]
# Example: go--install.sh golang.org/x/tools/gopls@latest

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

# The user the packages are installed for. 'coder' in a booth; the real user
# when provisioning a machine or a runner (see docs/REUSE_BOOTH.md).
CB_USER_NAME="${CB_USER_NAME:-coder}"

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [package@version...]"
        echo "Installs Go packages for the booth user (\$CB_USER_NAME, default 'coder'). No packages is a no-op."
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No Go packages requested is a no-op, not an error: the *-pkg templates emit
# `install go ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No Go packages requested; nothing to install."
    exit 0
fi

# The go binary used for the presence check (overridable for testing).
GO_BIN="${GO_BIN:-/usr/local/go-current/bin/go}"
if [ ! -x "$GO_BIN" ]; then
    echo "❌ Go is not installed. Run go--setup.sh first." >&2
    exit 1
fi

# Source go profile to set up GOPATH.
# A loop rather than `source <glob>`: an unmatched glob stays literal, and a
# `source` that cannot find its file is fatal under bash 3.2 before the
# `|| true` is ever reached. The loop also does the right thing if the glob ever
# matches more than one profile.
for go_profile in /etc/profile.d/*-cb-go--profile.sh; do
    [ -f "$go_profile" ] && source "$go_profile" 2>/dev/null || true
done
unset go_profile

# The commands the catalog installs (gopls and dlv in every Go booth, the protobuf
# plugins, golangci-lint, ...) come prebuilt from NawaMan/CodingBoothPrebuilt, at the
# version `go install` would pick (@latest through the module proxy, or the @vX.Y.Z
# asked for). They land where `go install` puts them, the booth user's GOBIN
# (~/go/bin, which the go profile puts on PATH). Anything else -- or a version with no
# asset yet -- is compiled below exactly as before.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-packages.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-packages.sh"

CB_USER_HOME="${CB_USER_HOME:-$(getent passwd "$CB_USER_NAME" 2>/dev/null | cut -d: -f6 || true)}"
CB_USER_HOME="${CB_USER_HOME:-/home/${CB_USER_NAME}}"
GO_BIN_DIR="${CB_USER_HOME}/go/bin"
PREBUILT_TMP="$(mktemp -d)"
trap 'rm -rf "$PREBUILT_TMP"' EXIT

TO_BUILD=()
for pkg in "$@"; do
    if found="$(cb_prebuilt_go "$pkg")"; then
        read -r tool version exe <<< "$found"
        if cb_prebuilt_install "$tool" "$version" native "$PREBUILT_TMP/$tool"; then
            install -d -o "$CB_USER_NAME" -g "$(id -gn "$CB_USER_NAME")" "$GO_BIN_DIR"
            install -m 755 -o "$CB_USER_NAME" -g "$(id -gn "$CB_USER_NAME")" \
                "$PREBUILT_TMP/$tool/bin/$exe" "$GO_BIN_DIR/$exe"
            echo "✅ $pkg → prebuilt $tool $version in $GO_BIN_DIR/$exe"
            continue
        fi
        echo "ℹ️  $tool $version: not prebuilt for this image; building with go install..."
    fi
    TO_BUILD+=("$pkg")
done
set -- ${TO_BUILD[@]+"${TO_BUILD[@]}"}

# Install packages as the booth user so they go to that user's GOPATH.
#
# `go install` fetches through proxy.golang.org, which resets connections often enough
# to fail a build outright — and go has no retry of its own, so a single reset takes the
# whole image down. Retry with a backoff. A package that is genuinely broken still fails,
# just three attempts later; a blip no longer costs a rebuild.
for pkg in "$@"; do
    attempt=1
    until sudo -u "$CB_USER_NAME" bash -lc "go install '$pkg'"; do
        if [ "$attempt" -ge 3 ]; then
            echo "❌ go install '$pkg' failed after ${attempt} attempts." >&2
            exit 1
        fi
        echo "⚠️  go install '$pkg' failed (attempt ${attempt}); retrying in $((attempt * 5))s..." >&2
        sleep "$((attempt * 5))"
        attempt=$((attempt + 1))
    done
done
