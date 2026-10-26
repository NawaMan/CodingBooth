#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Installs the toolchain a project pins in its lean-toolchain file into the image at
# BUILD time, so the first `lake` in the booth does not stop to download it -- and does
# not download it again in every fresh booth. Mathlib moves its pin often, so a
# Mathlib project's toolchain rarely matches the template's default one.
#
# The lean+toolchain-file extension copies only that file out of the project (never
# the whole folder, so editing source does not invalidate this layer):
#   copy .booth/Boothfile lean-toolchai[n] /tmp/cb-lean-toolchain/
#   setup lean-toolchain-file /tmp/cb-lean-toolchain
# The Boothfile is only there because a COPY needs at least one match.
# --------------------------

usage() {
    echo "Usage: $0 <dir>"
    echo "  Installs the toolchain pinned by <dir>/lean-toolchain."
    echo "  Does nothing when the file is not there."
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") usage >&2; exit 1 ;;
esac

[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }
HOME=/root

DIR="$1"
export ELAN_HOME="${ELAN_HOME:-/opt/elan}"
ELAN_BIN="${ELAN_BIN:-${ELAN_HOME}/bin/elan}"

cleanup() { [[ "$DIR" == /tmp/* ]] && rm -rf "$DIR" || true; }

if [ ! -f "$DIR/lean-toolchain" ]; then
    echo "ℹ️  No lean-toolchain in the project; the default toolchain is used."
    cleanup
    exit 0
fi

if [ ! -x "$ELAN_BIN" ]; then
    echo "❌ Lean is not installed. Run lean--setup.sh first." >&2
    exit 1
fi

TOOLCHAIN="$(tr -d ' \t\r\n' < "$DIR/lean-toolchain")"
if [ -z "$TOOLCHAIN" ]; then
    echo "❌ $DIR/lean-toolchain is empty." >&2
    exit 1
fi
cleanup

echo "📦 Installing the toolchain pinned by lean-toolchain: ${TOOLCHAIN}"
"$ELAN_BIN" toolchain install "$TOOLCHAIN"

# Keep what elan writes to at run time writable by the booth user (see lean--setup.sh).
# Not `chmod -R`: this runs in a later image layer than lean--setup.sh, so a recursive
# chmod would copy every file of every toolchain into this layer -- a minute of build
# and another GB. Root's umask already leaves the new toolchain world-readable.
for path in "$ELAN_HOME" "$ELAN_HOME"/toolchains "$ELAN_HOME"/tmp "$ELAN_HOME"/update-hashes \
            "$ELAN_HOME"/update-hashes/* "$ELAN_HOME"/settings.toml; do
    if [ -e "$path" ]; then chmod a+rwX "$path"; fi
done

echo "✅ Pinned toolchain installed: ${TOOLCHAIN}"
cat <<'EOF'
ℹ️ Ready to use: lean and lake in the project folder use the pinned toolchain.
   elan show              # which toolchain is active, and why
EOF
