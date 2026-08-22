#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Go packages for the 'coder' user.
# It requires go--setup.sh to have been run first.
# Usage: go--install.sh <package@version> [package@version...]
# Example: go--install.sh golang.org/x/tools/gopls@latest

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [package@version...]"
        echo "Installs Go packages for the 'coder' user. No packages is a no-op."
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

if [ ! -x /usr/local/go-current/bin/go ]; then
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

# Install packages as coder user so they go to coder's GOPATH.
#
# `go install` fetches through proxy.golang.org, which resets connections often enough
# to fail a build outright — and go has no retry of its own, so a single reset takes the
# whole image down. Retry with a backoff. A package that is genuinely broken still fails,
# just three attempts later; a blip no longer costs a rebuild.
for pkg in "$@"; do
    attempt=1
    until sudo -u coder bash -lc "go install '$pkg'"; do
        if [ "$attempt" -ge 3 ]; then
            echo "❌ go install '$pkg' failed after ${attempt} attempts." >&2
            exit 1
        fi
        echo "⚠️  go install '$pkg' failed (attempt ${attempt}); retrying in $((attempt * 5))s..." >&2
        sleep "$((attempt * 5))"
        attempt=$((attempt + 1))
    done
done
