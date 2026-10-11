#!/bin/bash
# Run by test--boothfile-rust.sh through `booth exec ... -- bash inBooth-rust.sh`: plain bash,
# NOT a login shell, so /etc/profile.d never runs. Everything below must work from the image
# environment alone. Prints one labeled line per check; the host side asserts on them.

# Pinned toolchain (rust-toolchain.toml in this folder), baked in at build by toolchain-file.
echo "pin-cargo: $(cargo --version 2>&1)"
echo "pin-wasm: $(rustup target list --installed 2>&1 | grep -c wasm32-unknown-unknown)"
echo "fmt: $(cargo fmt --version >/dev/null 2>&1 && echo ok || echo missing)"
echo "clippy: $(cargo clippy --version >/dev/null 2>&1 && echo ok || echo missing)"
echo "analyzer: $(rust-analyzer --version >/dev/null 2>&1 && echo ok || echo missing)"

# Default toolchain, outside the pinned folder: compile and run a program, then add a target
# as the booth user (the rustup home used to be read-only).
cd /tmp && rm -rf demo && cargo new -q demo && cd demo
echo "run: $(cargo run -q 2>&1 | tail -1)"
rustup target add wasm32-unknown-unknown >/dev/null 2>&1
echo "add-target: $(rustup target list --installed 2>&1 | grep -c wasm32-unknown-unknown)"
echo "wasm-build: $(cargo build -q --target wasm32-unknown-unknown 2>&1 && echo ok || echo failed)"
