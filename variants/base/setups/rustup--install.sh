#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# This script adds rustup targets or components to the booth's Rust toolchain.
# It requires rust--setup.sh to have been run first.
# Usage: rustup--install.sh target    <target>[,target...]
#        rustup--install.sh component <component>[,component...]
# Example: rustup--install.sh target wasm32-unknown-unknown,aarch64-unknown-linux-gnu
#          rustup--install.sh component llvm-tools,miri
#
# They go into the default toolchain baked into the image. A project that pins its
# own toolchain lists its targets and components in rust-toolchain.toml instead
# (see the rust+toolchain-file extension).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# cb_retry retries the network-bound rustup call below past a transient error
# (a 5xx, a dropped connection). The lib sits beside this script both in the
# image (/opt/codingbooth/setups/) and in the repo, so a host-run test finds it.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

usage() {
    echo "Usage: $0 target|component <name>[,name...]"
    echo "  $0 target wasm32-unknown-unknown"
    echo "  $0 component llvm-tools,miri"
}

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

KIND="${1:-}"
case "$KIND" in
    -h|--help) usage; exit 0 ;;
    target|component) shift ;;
    *) echo "❌ Unknown kind '${KIND}'" >&2; usage >&2; exit 1 ;;
esac

# Expand comma-separated names into separate arguments.
set -- $(echo "$@" | tr ',' ' ')

# No names is a no-op, not an error: the extensions emit
# `install rustup <kind> ${RUST_...}` with the list defaulting to empty, so failing
# here would break the image build of every project that selects one without names.
if [ $# -eq 0 ]; then
    echo "ℹ️  No rustup ${KIND}s requested; nothing to install."
    exit 0
fi

# Both overridable for testing.
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rust/rustup}"
RUSTUP_BIN="${RUSTUP_BIN:-/opt/rust/cargo/bin/rustup}"
if [ ! -x "$RUSTUP_BIN" ]; then
    echo "❌ Rust is not installed. Run rust--setup.sh first." >&2
    exit 1
fi

echo "📦 Adding rustup ${KIND}s: $*"
cb_retry "$RUSTUP_BIN" "$KIND" add "$@"

# Keep the rustup home writable by the booth user (rust--setup.sh makes it so;
# files this run added would otherwise be root-only).
chmod -R a+rwX "$RUSTUP_HOME"

echo "✅ rustup ${KIND}s added: $*"
"$RUSTUP_BIN" "$KIND" list --installed
