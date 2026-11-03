#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# Prolog setup — SWI-Prolog (default) or GNU Prolog, from Ubuntu's packages.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--impl <swi|gnu|both>]

Examples:
  $0                  # SWI-Prolog (swipl)
  $0 --impl gnu       # GNU Prolog (gprolog, gplc native compiler)
  $0 --impl both      # both side by side

Notes:
- SWI-Prolog installs without its XPCE GUI, except on a desktop variant
- Versions are whatever the distro ships; pin them with APT_SNAPSHOT
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_DIR="$(dirname "$0")"

# ---- defaults / args ----
IMPL="swi"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --impl)    shift; IMPL="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

PKGS=()
case "$IMPL" in
  swi|both)
    # The full swi-prolog package pulls in XPCE and X11; only worth it with a desktop.
    if "$SCRIPT_DIR/cb-has-desktop.sh"; then
      PKGS+=(swi-prolog)
    else
      PKGS+=(swi-prolog-nox)
    fi
    ;;&
  gnu|both)
    PKGS+=(gprolog)
    ;;&
  swi|gnu|both) ;;
  *) echo "❌ Unknown implementation: $IMPL (swi, gnu or both)" >&2; exit 2 ;;
esac

# ---- install ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
echo "📦 Installing ${PKGS[*]} ..."
apt-get install -y --no-install-recommends "${PKGS[@]}"
rm -rf /var/lib/apt/lists/*

# ---- summary ----
echo "✅ Prolog installed (${IMPL})."
if command -v swipl >/dev/null; then
  echo -n "   swipl   → "; swipl --version || true
fi
if command -v gprolog >/dev/null; then
  echo -n "   gprolog → "; gprolog --version 2>&1 | head -n1 || true
fi

cat <<'EON'
ℹ️ Ready to use:
- swipl hello.pl                      # SWI-Prolog REPL with a file loaded
- swipl -g main -t halt hello.pl      # run main/0 as a script
- gplc hello.pl -o hello              # GNU Prolog native compile (--impl gnu)
EON
