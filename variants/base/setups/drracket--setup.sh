#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Installs Racket and DrRacket from the apt 'racket' package
- The 'racket' command-line REPL works on any variant
- The DrRacket GUI requires a desktop environment (x11/VNC)
- See: https://docs.racket-lang.org/
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

echo "• Installing Racket + DrRacket from apt ..."
apt-get update
apt-get install -y --no-install-recommends racket
rm -rf /var/lib/apt/lists/*

# ---- summary ----
echo ""
echo "✅ Racket installed."
echo -n "   racket → "; racket --version 2>/dev/null || true
echo ""
echo "ℹ️  CLI REPL:    racket"
echo "   DrRacket GUI: drracket  (needs a desktop variant)"
echo "   Docs:         https://docs.racket-lang.org/"
echo "   Teaching:     https://htdp.org/"
