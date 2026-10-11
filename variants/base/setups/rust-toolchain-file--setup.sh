#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Installs the toolchain a project pins in rust-toolchain.toml (or the legacy
# rust-toolchain file) into the image at BUILD time, so the first `cargo` in the
# booth does not stop to download it -- and does not download it again in every
# fresh booth, since a booth's filesystem is thrown away when it exits.
#
# The rust+toolchain-file extension copies only those files out of the project
# (never the whole folder, so editing source does not invalidate this layer):
#   copy .booth/Boothfile rust-toolchai[n] rust-toolchain.tom[l] /tmp/cb-rust-toolchain/
#   setup rust-toolchain-file /tmp/cb-rust-toolchain
# The Boothfile is only there because a COPY needs at least one match.
# --------------------------

usage() {
    echo "Usage: $0 <dir>"
    echo "  Installs the toolchain pinned by <dir>/rust-toolchain.toml (or <dir>/rust-toolchain)."
    echo "  Does nothing when neither file is there."
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") usage >&2; exit 1 ;;
esac

[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }
HOME=/root

DIR="$1"
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rust/rustup}"
RUSTUP_BIN="${RUSTUP_BIN:-/opt/rust/cargo/bin/rustup}"

cleanup() { [[ "$DIR" == /tmp/* ]] && rm -rf "$DIR" || true; }

if [ ! -f "$DIR/rust-toolchain.toml" ] && [ ! -f "$DIR/rust-toolchain" ]; then
    echo "ℹ️  No rust-toolchain.toml in the project; the default toolchain is used."
    cleanup
    exit 0
fi

if [ ! -x "$RUSTUP_BIN" ]; then
    echo "❌ Rust is not installed. Run rust--setup.sh first." >&2
    exit 1
fi

cd "$DIR"
echo "📦 Installing the toolchain pinned by $(ls rust-toolchain.toml rust-toolchain 2>/dev/null | head -1)..."
# rustup 1.28+ installs the active toolchain -- with the targets and components
# the file lists -- from a bare `rustup toolchain install`; older rustup did it
# implicitly on `rustup show`.
"$RUSTUP_BIN" toolchain install || "$RUSTUP_BIN" show

# The same IDE components rust--setup.sh adds to the default toolchain, so
# rust-analyzer works on the pinned one too. A miss is a warning, not a failure.
for component in rust-analyzer rust-src; do
    "$RUSTUP_BIN" component add "$component" \
        || echo "⚠️  rustup could not add ${component} to the pinned toolchain; continuing without it"
done

TOOLCHAIN="$("$RUSTUP_BIN" show active-toolchain | awk '{print $1}')"
cd /
cleanup

# Keep the rustup home writable by the booth user (see rust--setup.sh).
chmod -R a+rwX "$RUSTUP_HOME"

echo "✅ Pinned toolchain installed: ${TOOLCHAIN}"
cat <<'EOF'
ℹ️ Ready to use: cargo and rustc in the project folder use the pinned toolchain.
   rustup show            # which toolchain is active, and why
EOF
