#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Rust crates for the 'coder' user.
# It requires rust--setup.sh to have been run first.
# Usage: cargo--install.sh [cargo-flags...] <crate[@version]> [crate[@version]...]
# Example: cargo--install.sh ripgrep fd-find bat
#          cargo--install.sh ripgrep@14.1.0
#          cargo--install.sh --locked ripgrep@14.1.0   # honor the crate's Cargo.lock (fixed dependency tree)
#
# Any leading-dash token (e.g. --locked) is passed through to `cargo install`.
# --locked pins the whole dependency tree to the crate's published Cargo.lock,
# instead of letting transitive deps float to newest-compatible at build time
# (see docs/REPRODUCIBILITY.md). It is opt-in because a crate that ships no
# Cargo.lock, or a stale one, makes --locked fail the build.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [cargo-flags...] <crate> [crate...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# Separate cargo flags (any leading-dash token, e.g. --locked) from crate specs,
# so the flags can be applied to every `cargo install` in this line.
FLAGS=()
SPECS=()
for arg in "$@"; do
    case "$arg" in
        -*) FLAGS+=("$arg") ;;
        *)  SPECS+=("$arg") ;;
    esac
done

# No crates requested is a no-op, not an error: the *-pkg templates emit
# `install cargo ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages. Checked before the toolchain probe so that
# `install cargo --locked ${CARGO_PKGS}` -- flags but no crates -- is a no-op too.
if [ ${#SPECS[@]} -eq 0 ]; then
    echo "ℹ️  No crates requested; nothing to install."
    exit 0
fi

# Path to the cargo binary used for the presence check (overridable for testing).
CARGO_BIN="${CARGO_BIN:-/opt/rust/cargo/bin/cargo}"
if [ ! -x "$CARGO_BIN" ]; then
    echo "❌ Rust is not installed. Run rust--setup.sh first." >&2
    exit 1
fi

# Install crates as coder user so they go to coder's ~/.cargo/bin
# Explicitly unset CARGO_HOME to use default ~/.cargo
# A trailing @version pins the crate (translated to cargo's --version flag).
for spec in "${SPECS[@]}"; do
    crate="${spec%@*}"
    if [ "$crate" = "$spec" ]; then
        echo "📦 Installing $crate..."
        sudo -u coder bash -lc "unset CARGO_HOME; cargo install '$crate' ${FLAGS[*]}"
    else
        version="${spec##*@}"
        echo "📦 Installing $crate (version $version)..."
        sudo -u coder bash -lc "unset CARGO_HOME; cargo install '$crate' --version '$version' ${FLAGS[*]}"
    fi
done
