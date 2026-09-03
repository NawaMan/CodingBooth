#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs Rust toolchain at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# --- Defaults ---
RUST_VERSION="${1:-stable}"

LEVEL=58                          # See README.md - Profile Ordering

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-rust--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-rust--profile.sh"

# Install build dependencies (linker, etc.)
apt-get update
apt-get install -y --no-install-recommends build-essential
rm -rf /var/lib/apt/lists/*

# Rust will be installed to /opt/rust (shared) with user cargo in ~/.cargo
export RUSTUP_HOME="/opt/rust/rustup"
export CARGO_HOME="/opt/rust/cargo"

echo "📦 Installing Rust ${RUST_VERSION} via rustup..."
# Staged to a file rather than piped: a retried transfer restarts from the
# beginning, so a consumer already reading the stream would see the truncated
# first attempt followed by the whole body. Downloading first removes that hazard
# and lets --retry-all-errors cover a registry 5xx.
# `sh -s --` existed only to read the script from stdin; with a file the args go
# straight to it.
RUSTUP_INIT="$(mktemp)"
curl --proto '=https' --tlsv1.2 -sSf --retry 5 --retry-delay 3 --retry-all-errors -o "$RUSTUP_INIT" https://sh.rustup.rs
sh "$RUSTUP_INIT" -y --no-modify-path --default-toolchain "${RUST_VERSION}"
rm -f "$RUSTUP_INIT"

# Make the shared installation readable
chmod -R a+rX /opt/rust

# Create symlinks for rustc, cargo, rustup in /usr/local/bin
ln -sf "${CARGO_HOME}/bin/rustc" /usr/local/bin/rustc
ln -sf "${CARGO_HOME}/bin/cargo" /usr/local/bin/cargo
ln -sf "${CARGO_HOME}/bin/rustup" /usr/local/bin/rustup

# Verify installation
echo "• Verifying installation..."
"${CARGO_HOME}/bin/rustc" --version
"${CARGO_HOME}/bin/cargo" --version

# ---- Create startup file: to be executed as normal user on first login ----
cat > "${STARTUP_FILE}" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SENTINEL="$HOME/.rust-startup-done"
[[ -f "$SENTINEL" ]] || {
  mkdir -p "$HOME/.cargo/bin"
  touch "$SENTINEL"
}
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: to be sourced at the beginning of a user shell session ----
cat > "${PROFILE_FILE}" << 'EOF'
# Profile: Rust

# Shared rustup installation (toolchains are read-only)
export RUSTUP_HOME="/opt/rust/rustup"

# CARGO_HOME is NOT set - defaults to ~/.cargo for user-writable registry/cache
# This allows users to install crates to their own directory

# Add shared cargo bin to PATH (rustc, cargo, rustup binaries)
case ":$PATH:" in
  *":/opt/rust/cargo/bin:"*) ;;
  *) export PATH="/opt/rust/cargo/bin:$PATH";;
esac

# Add user's cargo bin to PATH (for user-installed crates)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH";;
esac
EOF
chmod 644 "${PROFILE_FILE}"

echo "✅ .... Rust is installed ...."
echo "• Version: ${RUST_VERSION}"
echo "• RUSTUP_HOME: ${RUSTUP_HOME}"
echo "• CARGO_HOME: ${CARGO_HOME}"
echo "• Startup file: ${STARTUP_FILE}"
echo "• Profile file: ${PROFILE_FILE}"
echo ""
echo "You may source the profile above to start using Rust in this session."
