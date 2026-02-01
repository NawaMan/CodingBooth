#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Rust crates for the 'coder' user.
# It requires rust--setup.sh to have been run first.
# Usage: cargo--install.sh <crate> [crate...]
# Example: cargo--install.sh ripgrep fd-find bat

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <crate> [crate...]" >&2
    exit 1
fi

if [ ! -x /opt/rust/cargo/bin/cargo ]; then
    echo "❌ Rust is not installed. Run rust--setup.sh first." >&2
    exit 1
fi

# Install crates as coder user so they go to coder's ~/.cargo/bin
# Explicitly unset CARGO_HOME to use default ~/.cargo
for crate in "$@"; do
    echo "📦 Installing $crate..."
    sudo -u coder bash -lc "unset CARGO_HOME; cargo install '$crate'"
done
